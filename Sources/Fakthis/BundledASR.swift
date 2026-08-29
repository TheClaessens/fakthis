import FluidAudio
import Foundation
import whisper

extension BundledTranscriber {
    public static func production(models: URL) -> BundledTranscriber {
        let asr = BundledASR(models: models)
        return BundledTranscriber(
            capture: MicrophoneTakeCapture(),
            parakeet: { try await asr.parakeet($0, boost: $1) },
            whisper: { try await asr.whisper($0, prompt: $1) },
            compile: { await asr.status() }
        )
    }
}

actor BundledASR {
    private let models: URL
    private var asr: AsrManager?
    private var ctc: CtcModels?
    private var tokenizer: CtcTokenizer?
    private var whisperContext: OpaquePointer?
    private var compiled = false

    private var ctcDirectory: URL {
        models.appending(component: "parakeet-ctc-110m-coreml")
    }

    init(models: URL) {
        self.models = models
        ModelHub.offlineMode = true
        Task { await self.load() }
    }

    func status() -> CompileStatus {
        compiled ? .done : .inProgress
    }

    func parakeet(_ samples: [Float], boost: [BoostTerm]) async throws -> String {
        guard let asr else { throw TranscribeFailed() }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(samples, decoderState: &state)
        guard !boost.isEmpty, let ctc, let tokenizer, let timings = result.tokenTimings else {
            return result.text
        }
        return await boosted(
            text: result.text,
            timings: timings,
            samples: samples,
            boost: boost,
            ctc: ctc,
            tokenizer: tokenizer
        ) ?? result.text
    }

    /// FluidAudio's `VocabularyBoostingSession` loads the CTC tokenizer from
    /// Application Support. We keep weights in the app bundle, so we tokenize
    /// here and point the rescorer at the bundled CTC directory.
    private func boosted(
        text: String,
        timings: [TokenTiming],
        samples: [Float],
        boost: [BoostTerm],
        ctc: CtcModels,
        tokenizer: CtcTokenizer
    ) async -> String? {
        let context = CustomVocabularyContext(
            terms: boost.map {
                CustomVocabularyTerm(
                    text: $0.text,
                    aliases: $0.aliases.isEmpty ? nil : $0.aliases,
                    ctcTokenIds: tokenizer.encode($0.text)
                )
            }
        )
        let spotter = CtcKeywordSpotter(models: ctc, blankId: ctc.vocabulary.count)
        guard
            let rescorer = try? await VocabularyRescorer.create(
                spotter: spotter,
                vocabulary: context,
                ctcModelDirectory: ctcDirectory
            )
        else {
            return nil
        }
        do {
            let spotted = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: context,
                minScore: nil
            )
            guard !spotted.logProbs.isEmpty else { return nil }
            let size = ContextBiasingConstants.rescorerConfig(forVocabSize: context.terms.count)
            let rescored = rescorer.ctcTokenRescore(
                transcript: text,
                tokenTimings: timings,
                logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration,
                cbw: size.cbw,
                marginSeconds: 0.5,
                minSimilarity: max(size.minSimilarity, context.minSimilarity)
            )
            return rescored.wasModified ? rescored.text : nil
        } catch {
            return nil
        }
    }

    func whisper(_ samples: [Float], prompt: String) async throws -> String {
        guard let whisperContext else { throw TranscribeFailed() }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.carry_initial_prompt = true
        return try prompt.withCString { pointer in
            params.initial_prompt = pointer
            let code = samples.withUnsafeBufferPointer { buffer in
                whisper_full(
                    whisperContext,
                    params,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            guard code == 0 else { throw TranscribeFailed() }
            let segmentCount = whisper_full_n_segments(whisperContext)
            var segments: [String] = []
            segments.reserveCapacity(Int(segmentCount))
            for segment in 0..<segmentCount {
                if let raw = whisper_full_get_segment_text(whisperContext, segment) {
                    segments.append(String(cString: raw))
                }
            }
            return segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func load() async {
        defer { compiled = true }
        asr = await loadParakeet()
        await loadCTC()
        whisperContext = loadWhisper()
    }

    private func loadParakeet() async -> AsrManager? {
        let directory = models.appending(component: "parakeet-tdt-0.6b-v3-coreml")
        do {
            let loaded = try await AsrModels.load(
                from: directory,
                configuration: AsrModels.defaultConfiguration(),
                version: .v3
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(loaded)
            return manager
        } catch {
            return nil
        }
    }

    private func loadCTC() async {
        ctc = try? await CtcModels.loadDirect(from: ctcDirectory, variant: .ctc110m)
        tokenizer = try? await CtcTokenizer.load(from: ctcDirectory)
    }

    private func loadWhisper() -> OpaquePointer? {
        let weights = models.appending(component: "ggml-large-v3-turbo.bin")
        let params = whisper_context_default_params()
        return weights.path.withCString { whisper_init_from_file_with_params($0, params) }
    }
}
