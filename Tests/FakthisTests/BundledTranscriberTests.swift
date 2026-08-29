import Foundation
import Testing
import Fakthis

@Test func emptyBoostListMeansParakeetRunsWithoutBoostTerms() async throws {
    let parakeet = ScriptedParakeet(text: "scan the bin")
    let whisper = ScriptedWhisper()
    let capture = ScriptedCapture(samples: [0.1, 0.2])
    let transcriber = BundledTranscriber(
        capture: capture,
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { try await whisper.transcribe($0, prompt: $1) }
    )

    await transcriber.beginTake()
    let take = try await transcriber.transcribe(boostList: [])

    #expect(take == "scan the bin")
    #expect(await parakeet.boostLists == [[]])
    #expect(await parakeet.samples == [[0.1, 0.2]])
    #expect(await whisper.prompts.isEmpty)
}

@Test func parakeetBoostListGetsMechanicalAliasesAndTypedAlias() async throws {
    let parakeet = ScriptedParakeet(text: "scan the bin")
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: [0.5]),
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { _, _ in throw TranscribeFailed() }
    )
    await transcriber.beginTake()
    _ = try await transcriber.transcribe(boostList: ["SM-A-rt / smarty", "pick screen"])

    let boost = try #require(await parakeet.boostLists.first)
    #expect(boost.map(\.text) == ["SM-A-rt", "pick screen"])
    let smart = try #require(boost.first)
    #expect(smart.aliases.contains("smart"))
    #expect(smart.aliases.contains("S M A R T"))
    #expect(smart.aliases.contains("smarty"))
    let pick = try #require(boost.last)
    #expect(pick.aliases.contains("pickscreen"))
    #expect(pick.aliases.contains("pick-screen"))
    #expect(!pick.aliases.contains("P I C K S C R E E N"))
}

@Test func boostListHardStopsAtTwoHundredThirtyTerms() async throws {
    let parakeet = ScriptedParakeet(text: "scan the bin")
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: [0.5]),
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { _, _ in throw TranscribeFailed() }
    )
    await transcriber.beginTake()
    _ = try await transcriber.transcribe(boostList: (1...231).map { "term-\($0)" })

    let boost = try #require(await parakeet.boostLists.first)
    #expect(boost.count == TranscriberBoost.hardStop)
    #expect(boost.first?.text == "term-1")
    #expect(boost.last?.text == "term-230")
}

@Test func whisperFallbackPromptUsesCanonicalBoostTextsNotTypedAliasEncoding() async throws {
    let parakeet = ScriptedParakeet(text: "unused")
    await parakeet.setFail(true)
    let whisper = ScriptedWhisper()
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: [0.5]),
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { try await whisper.transcribe($0, prompt: $1) }
    )
    await transcriber.beginTake()
    _ = try await transcriber.transcribe(boostList: ["SM-A-rt / smarty", "pick screen"])

    let prompt = try #require(await whisper.prompts.first)
    #expect(prompt.split(separator: " ").map(String.init) == ["pick", "screen", "SM-A-rt"])
    #expect(!prompt.contains("smarty"))
    #expect(!prompt.contains("/"))
}

@Test func parakeetFailureFallsBackToWhisperWithHighestValueLast() async throws {
    let parakeet = ScriptedParakeet(text: "unused")
    await parakeet.setFail(true)
    let whisper = ScriptedWhisper()
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: [0.5]),
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { try await whisper.transcribe($0, prompt: $1) }
    )
    await transcriber.beginTake()
    let take = try await transcriber.transcribe(boostList: (1...250).map { "term-\($0)" })

    #expect(take == "whisper take")
    let prompt = try #require(await whisper.prompts.first)
    let tokens = prompt.split(separator: " ").map(String.init)
    #expect(tokens.count == TranscriberBoost.whisperTokens)
    #expect(tokens.first == "term-223")
    #expect(tokens.last == "term-1")
    #expect(await whisper.samples == [[0.5]])
}

@Test func compileStatusComesFromTheInjectedCompile() async throws {
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: []),
        parakeet: { _, _ in "" },
        whisper: { _, _ in "" },
        compile: { .inProgress }
    )
    #expect(await transcriber.compileStatus() == .inProgress)
}

@Test func bothEnginesFailingIsAFailedTake() async throws {
    let parakeet = ScriptedParakeet(text: "unused")
    await parakeet.setFail(true)
    let whisper = ScriptedWhisper()
    await whisper.setFail(true)
    let transcriber = BundledTranscriber(
        capture: ScriptedCapture(samples: [0.5]),
        parakeet: { try await parakeet.transcribe($0, boost: $1) },
        whisper: { try await whisper.transcribe($0, prompt: $1) }
    )
    await transcriber.beginTake()
    await #expect(throws: TranscribeFailed.self) {
        try await transcriber.transcribe(boostList: ["bin"])
    }
}

private actor ScriptedParakeet {
    var text: String
    var fail = false
    private(set) var boostLists: [[BoostTerm]] = []
    private(set) var samples: [[Float]] = []

    init(text: String) {
        self.text = text
    }

    func setFail(_ value: Bool) {
        fail = value
    }

    func transcribe(_ samples: [Float], boost: [BoostTerm]) async throws -> String {
        self.samples.append(samples)
        self.boostLists.append(boost)
        if fail { throw TranscribeFailed() }
        return text
    }
}

private actor ScriptedWhisper {
    var text = "whisper take"
    var fail = false
    private(set) var prompts: [String] = []
    private(set) var samples: [[Float]] = []

    func setFail(_ value: Bool) {
        fail = value
    }

    func transcribe(_ samples: [Float], prompt: String) async throws -> String {
        self.samples.append(samples)
        prompts.append(prompt)
        if fail { throw TranscribeFailed() }
        return text
    }
}

private actor ScriptedCapture: TakeCapture {
    var samples: [Float]
    private var began = false

    init(samples: [Float]) {
        self.samples = samples
    }

    func begin() async {
        began = true
    }

    func finish() async throws -> [Float] {
        guard began else { throw TranscribeFailed() }
        began = false
        return samples
    }
}
