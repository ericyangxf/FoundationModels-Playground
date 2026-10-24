import Foundation
import FoundationModels

/// The model every page runs on, and the one place that picks it.
///
/// Gemma 4 E4B isn't part of the system the way Apple's model is: the app
/// downloads its 3.66 GB `.litertlm` file from Hugging Face once and keeps it
/// in Application Support. Every page still talks to it through a stock
/// `LanguageModelSession`, so going back to Apple's model means returning
/// `SystemLanguageModel` from `languageModel` and dropping the download.
@MainActor
@Observable
final class OnDeviceModel {
    static let shared = OnDeviceModel()

    enum Status: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case ready
        case failed(String)
    }

    private(set) var status: Status

    let displayName = "Gemma 4 E4B"

    nonisolated static let remoteURL = URL(
        string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm"
    )!

    /// What the Hugging Face file weighs, for the download button and for
    /// progress when the server doesn't send a length.
    nonisolated static let downloadSize: Int64 = 3_659_530_240

    nonisolated static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "gemma-4-E4B-it.litertlm")
    }

    /// The download lands under a temporary name and is moved into place
    /// only once complete, so a file at `fileURL` is always a whole one.
    nonisolated static var isOnDisk: Bool {
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    /// The usage metadata keys the executor reports decode speed, and whether
    /// that step ran with speculative decoding, under.
    nonisolated static let decodeSpeedKey = "decodeTokensPerSecond"
    nonisolated static let speculativeDecodingKey = "speculativeDecoding"
    /// Set when a step's free JSON didn't fit its schema and was rewritten
    /// under the llguidance constraint.
    nonisolated static let constrainedRetryKey = "constrainedRetry"

    /// The language model sessions are built on.
    nonisolated static let languageModel = GemmaLanguageModel(
        modelPath: fileURL.path(percentEncoded: false)
    )

    private init() {
        status = Self.isOnDisk ? .ready : .notDownloaded
    }

    /// Loads the weights ahead of the first question. The first load on a
    /// device also compiles the GPU kernels, which takes a while; later loads
    /// reuse what that left in Caches.
    func prewarm() {
        guard status == .ready else { return }
        LanguageModelSession(model: Self.languageModel).prewarm()
    }

    func download() {
        switch status {
        case .downloading, .ready: return
        case .notDownloaded, .failed: break
        }
        status = .downloading(fraction: 0)
        Task {
            do {
                try await ModelDownload(to: Self.fileURL) { fraction in
                    Task { @MainActor in
                        guard case .downloading = self.status else { return }
                        self.status = .downloading(fraction: fraction)
                    }
                }.run(from: Self.remoteURL)
                status = .ready
                prewarm()
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

/// What the model is thinking right now, for a page to show while it waits.
///
/// Foundation Models publishes a response's thinking when the response
/// itself next changes, not as it is thought — a parse that thinks for ten
/// seconds and then writes its JSON shows nothing until the end. So the
/// executor also reports each thought here as it streams. Turns run one at a
/// time, so there is only ever one thought in flight.
@MainActor
@Observable
final class ModelActivity {
    static let shared = ModelActivity()

    /// The thinking of the turn in flight, so far.
    private(set) var thought = ""
    /// True while that turn is still thinking, before its answer starts.
    private(set) var isThinking = false

    private init() {}

    func beginTurn() {
        thought = ""
        isThinking = false
    }

    func think(_ delta: String) {
        thought += delta
        isThinking = true
    }

    func endThinking() {
        isThinking = false
    }
}

/// One download of the model file, reporting progress as it goes and moving
/// the finished file into place before it reports success.
///
/// A plain foreground session: leaving the app pauses it, and coming back
/// to a failed download means starting it again.
private nonisolated final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    // Delegate callbacks arrive one at a time on the session's own serial
    // queue, which is what makes the mutable state below safe.
    private var continuation: CheckedContinuation<Void, Error>?
    private var finishError: Error?
    private var reported = 0.0

    init(to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(from url: URL) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : OnDeviceModel.downloadSize
        let fraction = min(Double(totalBytesWritten) / Double(total), 1)
        // A step per half percent is plenty for a progress bar.
        guard fraction - reported >= 0.005 else { return }
        reported = fraction
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            let manager = FileManager.default
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Moved under a temporary name first, so a crash mid-move can't
            // leave a partial file where `isOnDisk` looks.
            let partial = destination.appendingPathExtension("partial")
            try? manager.removeItem(at: partial)
            try manager.moveItem(at: location, to: partial)
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: partial, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = destination
            try excluded.setResourceValues(values)
        } catch {
            finishError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? finishError {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
