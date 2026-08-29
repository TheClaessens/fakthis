import Foundation

public protocol TakeCapture: Sendable {
    func begin() async
    func finish() async throws -> [Float]
}

public struct BoostTerm: Equatable, Sendable {
    public var text: String
    public var aliases: [String]

    public init(text: String, aliases: [String] = []) {
        self.text = text
        self.aliases = aliases
    }
}

public actor BundledTranscriber: Transcriber {
    private let capture: any TakeCapture
    private let parakeet: @Sendable ([Float], [BoostTerm]) async throws -> String
    private let whisper: @Sendable ([Float], String) async throws -> String
    private let compile: @Sendable () async -> CompileStatus

    public init(
        capture: any TakeCapture,
        parakeet: @escaping @Sendable ([Float], [BoostTerm]) async throws -> String,
        whisper: @escaping @Sendable ([Float], String) async throws -> String,
        compile: @escaping @Sendable () async -> CompileStatus = { .done }
    ) {
        self.capture = capture
        self.parakeet = parakeet
        self.whisper = whisper
        self.compile = compile
    }

    public func compileStatus() async -> CompileStatus {
        await compile()
    }

    public func beginTake() async {
        await capture.begin()
    }

    public func transcribe(boostList: [String]) async throws -> String {
        let samples: [Float]
        do {
            samples = try await capture.finish()
        } catch {
            throw TranscribeFailed()
        }
        let boost = Self.boostTerms(from: boostList)
        do {
            return try await parakeet(samples, boost)
        } catch {
            do {
                return try await whisper(samples, Self.whisperPrompt(from: boost.map(\.text)))
            } catch {
                throw TranscribeFailed()
            }
        }
    }

    static func boostTerms(from terms: [String]) -> [BoostTerm] {
        Array(terms.prefix(TranscriberBoost.hardStop)).map { term in
            let (text, typed) = typedAlias(in: term)
            return BoostTerm(text: text, aliases: unique(mechanicalAliases(of: text) + typed))
        }
    }

    static func whisperPrompt(from terms: [String]) -> String {
        let tokens = terms.reversed().flatMap { $0.split { $0.isWhitespace }.map(String.init) }
        return tokens.suffix(TranscriberBoost.whisperTokens).joined(separator: " ")
    }

    private static func typedAlias(in term: String) -> (String, [String]) {
        guard let slash = term.range(of: " / ") else { return (term, []) }
        let text = String(term[..<slash.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let alias = String(term[slash.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !alias.isEmpty else { return (term, []) }
        return (text, [alias])
    }

    private static func mechanicalAliases(of text: String) -> [String] {
        var aliases: [String] = []
        let compact = text.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        let compactLower = compact.lowercased()
        if compactLower != text, compactLower != text.lowercased() {
            aliases.append(compactLower)
        }
        if text.contains("-") || !text.contains(" "), compact.count > 1 {
            let letterSpaced = compact.uppercased().map(String.init).joined(separator: " ")
            if letterSpaced != text {
                aliases.append(letterSpaced)
            }
        }
        let dehyphenated = text.replacingOccurrences(of: "-", with: " ")
        if dehyphenated != text { aliases.append(dehyphenated) }
        let hyphenated = text.replacingOccurrences(of: " ", with: "-")
        if hyphenated != text { aliases.append(hyphenated) }
        return aliases
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
