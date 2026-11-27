import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
struct TranscriptPersistenceTests {
    @Test
    @MainActor
    func transcriptPersistenceIsOffByDefaultAndOptInPersists() throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        #expect(!session.isTranscriptPersistenceEnabled)
        #expect(!session.savesTranscriptTimestamps)

        session.isTranscriptPersistenceEnabled = true
        session.savesTranscriptTimestamps = true
        let restored = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults,
            transcriptsDirectoryURL: directory
        )

        #expect(restored.isTranscriptPersistenceEnabled)
        #expect(restored.savesTranscriptTimestamps)
    }

    @Test
    @MainActor
    func stopDoesNotCreateTranscriptFilesWhenPersistenceIsDisabled() async throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        await deliverTranscript("Stop must not persist this text.", to: session)
        session.stop()

        #expect(session.lines.last?.sourceText == "Stop must not persist this text.")
        #expect(transcriptFiles(in: directory).isEmpty)
    }

    @Test
    @MainActor
    func quitDoesNotCreateTranscriptFilesWhenPersistenceIsDisabled() async throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        await deliverTranscript("Quit must not persist this text.", to: session)
        session.prepareForTermination()

        #expect(session.lines.last?.sourceText == "Quit must not persist this text.")
        #expect(transcriptFiles(in: directory).isEmpty)
    }

    @Test(arguments: [false, true])
    @MainActor
    func emptyOpenAIRealtimeCaptureDoesNotCreateARecord(stopsRecording: Bool) throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        session.isRunning = false
        session.useOpenAIMode(.translation)
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = .originalAndTranslation
        #expect(session.isUsingOpenAIRealtimeTranslation)

        if stopsRecording {
            _ = session.activateLiveCallbackPipelineForTesting()
            session.stop()
        } else {
            session.prepareForTermination()
        }

        #expect(transcriptFiles(in: directory).isEmpty)
        #expect(session.savedTranscripts.isEmpty)
    }

    @Test(arguments: SavedTranscriptContentMode.allCases)
    @MainActor
    func openAIRealtimeSavesTranslationOnlyAccordingToContentSetting(mode: SavedTranscriptContentMode) async throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        session.isRunning = false
        session.useOpenAIMode(.translation)
        session.isDubbingEnabled = false
        session.isTranscriptPersistenceEnabled = true
        session.savedTranscriptContentMode = mode
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        let translation = "Translation with no source transcript."
        session.liveSpeechTranscriber(pipeline.transcriber, didTranslate: translation, language: .english, confidence: 1)
        for _ in 0..<50 {
            if session.lines.last?.translatedText == translation { break }
            await Task.yield()
        }
        try #require(session.lines.last?.translatedText == translation)

        session.prepareForTermination()

        let files = transcriptFiles(in: directory)
        if mode == .original {
            #expect(files.isEmpty)
        } else {
            #expect(files.count == 1)
            let saved = try #require(files.first)
            #expect(try String(contentsOf: saved, encoding: .utf8) == translation)
            #expect(saved.lastPathComponent.hasSuffix("_translation.txt") == (mode == .originalAndTranslation))
            #expect(session.savedTranscripts.first?.title == translation)
        }
    }

    @Test
    @MainActor
    func optInPersistenceStillWritesTheSelectedTranscriptContent() async throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        session.isTranscriptPersistenceEnabled = true
        await deliverTranscript("Opt-in persistence writes this text.", to: session)
        session.stop()

        let savedText = transcriptFiles(in: directory)
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        #expect(savedText.contains("Opt-in persistence writes this text."))
        #expect(!savedText.hasPrefix("["))
    }

    @Test
    @MainActor
    func savedCaptionsCarryMatchingElapsedTimestamps() throws {
        let (session, directory, defaults, suiteName) = try makeSession()
        defer { cleanup(directory: directory, defaults: defaults, suiteName: suiteName) }

        session.useTranslationMode()
        session.isTranscriptPersistenceEnabled = true
        session.savesTranscriptTimestamps = true
        session.savedTranscriptContentMode = .originalAndTranslation
        _ = session.activateLiveCallbackPipelineForTesting()
        let now = Date()
        session.lines = [
            CaptionLine(sourceText: "First caption.", translatedText: "第一段。", createdAt: now, isFinal: true),
            CaptionLine(sourceText: "Second caption.", translatedText: "第二段。", createdAt: now.addingTimeInterval(3), isFinal: true),
        ]
        session.prepareForTermination()

        let files = transcriptFiles(in: directory)
        let sourceURL = try #require(files.first { $0.lastPathComponent.hasSuffix("_original.txt") })
        let translationURL = try #require(files.first { $0.lastPathComponent.hasSuffix("_translation.txt") })
        let source = try String(contentsOf: sourceURL, encoding: .utf8).components(separatedBy: "\n\n")
        let translation = try String(contentsOf: translationURL, encoding: .utf8).components(separatedBy: "\n\n")
        #expect(source.map { String($0.prefix(15)) } == translation.map { String($0.prefix(15)) })
        #expect(source.first?.hasPrefix("[00:00:00.") == true)
        #expect(source.last?.hasPrefix("[00:00:03.") == true)
        #expect(source.map(SavedTranscriptTimestamp.removingPrefix(from:)) == ["First caption.", "Second caption."])
        #expect(translation.map(SavedTranscriptTimestamp.removingPrefix(from:)) == ["第一段。", "第二段。"])
        #expect(session.savedTranscripts.first?.title == "First caption.")
    }

    @MainActor
    private func makeSession() throws -> (
        TranslationSessionStore,
        URL,
        UserDefaults,
        String
    ) {
        let suiteName = "TranscriptPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateTranscriptPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults,
            transcriptsDirectoryURL: directory
        )
        session.useTranscribeOnlyMode()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.isRunning = true
        return (session, directory, defaults, suiteName)
    }

    @MainActor
    private func deliverTranscript(_ text: String, to session: TranslationSessionStore) async {
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        session.liveSpeechTranscriber(
            pipeline.transcriber,
            didRecognize: text,
            language: .english,
            confidence: 0.9
        )

        for _ in 0..<50 {
            if session.lines.last?.sourceText == text {
                return
            }
            await Task.yield()
        }
    }

    private func transcriptFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "txt" } ?? []
    }

    private func cleanup(directory: URL, defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
