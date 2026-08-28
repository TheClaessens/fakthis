---
status: accepted
---

# Transcribe locally on the Neural Engine with a bundled model, defaulting to Parakeet v3

Voice is the feature that removes the "PMs don't have time" bottleneck, and the design says audio never leaves the machine. That left the engine open. Fakthis transcribes with NVIDIA Parakeet TDT 0.6B v3 through FluidAudio — a Swift package running CoreML on the Apple Neural Engine — with whisper.cpp `large-v3-turbo` bundled as the fallback. Both ship inside the app; neither reaches the network.

The deciding requirement was not accuracy in general but **Dutch/English code-switching mid-sentence**, which is how Faktion actually speaks.

## Considered Options

**Whisper, in any wrapper.** Whisper commits to one `<|language|>` token per 30-second window. This is not a configuration choice: `whisper.cpp` auto-detects once at offset 0 and pins `state->lang_id` for the whole call, `mlx-whisper` detects from the first 30 seconds and sets the language once per file, and the tokenizer emits a single language token after `<|startoftranscript|>`. The shared BPE vocabulary means the token biases rather than hard-constrains, so English words *can* survive a Dutch-tokened transcript — but the bias is real and it is the documented failure mode. Kept as the fallback and the prototype's baseline, not as the default.

**Parakeet TDT 0.6B v3.** Chosen. It has no language token to get wrong: it detects language itself and decodes into one shared multilingual SentencePiece vocabulary. Dutch is among its stronger languages (7.48% FLEURS WER published by NVIDIA, independently measured at 7.8% by FluidAudio on an M4 Pro), and it runs at ~85x realtime on a base M2 Air.

**Apple's Speech framework.** Rejected on availability, not quality. `SpeechTranscriber`, the WWDC25 model, does not support Dutch — verified by runtime query, since Apple publishes no static locale list. `DictationTranscriber` does support nl-NL *and* nl-BE on-device, and is the only option anywhere that treats Flemish as a distinct locale, but its models cannot be bundled or pre-seeded and always need a first-run fetch from Apple. `SFSpeechRecognizer` caps a task at one minute and carries Apple's own warning against sensitive audio.

**faster-whisper / CTranslate2.** Has the best biasing API of any Whisper wrapper, and is CPU-only on Apple Silicon: `enum class Device { CPU, CUDA };` is the whole device enum.

## Consequences

- **This constrains the runtime.** FluidAudio is a Swift package on CoreML and the ANE, and whisper.cpp is a C++ library. A browser context cannot host either, so a PWA is out; a cross-platform shell would need a native sidecar. Fakthis is Apple-Silicon-macOS-shaped by this decision more than by any other.
- **The app ships with a model inside it and downloads nothing on first run.** whisper.cpp weights are MIT and are plain files; FluidAudio's `ModelHub.offlineMode` makes runtime fetching throw rather than silently reach out. Budget 350 MB–1.6 GB of bundle depending on quantisation, and a one-off first-launch delay while the ANE compiles the CoreML model.
- **Fakthis holds a custom vocabulary, and the Catalog is the natural source for it.** FluidAudio implements word boosting with aliases — `CustomVocabularyTerm(text: "SM-A-rt", aliases: ["smart", "S M A R T"])` — which maps predictable mishearings back to the canonical spelling. The Catalog already exists to supply domain vocabulary as Context; that same vocabulary is what the transcriber needs. Biasing costs throughput (~85x to ~26x realtime) and +130 MB.
- **The engine is a seam, not a commitment.** The default may flip to the fallback if measurement says so; what does not change is bundled local ASR on the ANE behind one interface. Two engines are bundled deliberately, because the brain-dump tier and the short-chat-answer tier may not want the same one.
- **The short-answer tier is the risk, and it is unmeasured.** No vendor documents code-switching behaviour for any option, and no benchmark separates Flemish from Netherlandic Dutch, so no published number describes Thomas's voice. FluidAudio further documents that short utterances with ambiguous audio can emit wrong-language tokens, and their alphabet-based mitigation does nothing for two Latin-script languages. Validated by prototype, not by this ADR.

Full research with citations: `.scratch/fakthis/research/03-transcription-engine.md`. Decision ticket: https://github.com/TheClaessens/fakthis/issues/4
