import AppKit
import Foundation

/// The one Spis backend process for the app's lifetime. Spawned lazily on
/// first use as `spis serve --port 0` from the located spis checkout, which
/// binds the loopback address on a port the system chooses and prints a
/// single ready line naming that port; the process then serves HTTP until the
/// app kills it on quit.
actor SpisBackendProcess {
    private var process: Process?
    private var baseURL: URL?
    private var terminationObserver: NSObjectProtocol?

    /// The loopback base URL of the running backend, spawning it on first
    /// use or after a death.
    func endpoint() async throws -> URL {
        if let process, process.isRunning, let baseURL { return baseURL }
        stop()

        guard let spis = SpisExecutable.locate() else {
            throw SpisBackendError.notInstalled
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = spis.url
        process.arguments = ["serve", "--port", "0"]
        process.currentDirectoryURL = spis.workingDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw SpisBackendError.failedToStart(error.localizedDescription)
        }
        self.process = process
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            process.terminate()
        }

        do {
            let port = try await Self.awaitReady(
                process: process,
                stdout: stdout.fileHandleForReading,
                stderr: stderr.fileHandleForReading
            )
            let base = URL(string: "http://127.0.0.1:\(port)")!
            baseURL = base
            return base
        } catch {
            process.terminate()
            self.process = nil
            if let terminationObserver {
                NotificationCenter.default.removeObserver(terminationObserver)
            }
            terminationObserver = nil
            throw error
        }
    }

    /// Kills the backend, if one is running.
    func stop() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        process?.terminate()
        process = nil
        baseURL = nil
    }

    /// Waits for the single ready line the backend prints once it has bound
    /// its port. Any other outcome — exit, unreadable line — is a start
    /// failure reported with the backend's own stderr.
    private static func awaitReady(
        process: Process,
        stdout: FileHandle,
        stderr: FileHandle
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let state = ReadyHandshake()
            state.attach(stdout: stdout, stderr: stderr)
            let finish: @Sendable (Result<Int, Error>) -> Void = { result in
                state.finish {
                    continuation.resume(with: result)
                }
            }
            stderr.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                state.appendError(String(decoding: data, as: UTF8.self))
            }
            stdout.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    finish(
                        .failure(
                            SpisBackendError.failedToStart(
                                "It exited before reporting its port." + state.stderrSuffix()
                            )))
                    return
                }
                guard let line = state.appendOutput(data) else { return }
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    (object["ready"] as? Bool) == true,
                    let port = object["port"] as? Int
                {
                    finish(.success(port))
                } else {
                    finish(
                        .failure(
                            SpisBackendError.failedToStart(
                                "Its ready line could not be read: "
                                    + String(decoding: line, as: UTF8.self) + "."
                                    + state.stderrSuffix()
                            )))
                }
            }
            // No clock: the backend answers with its ready line, or its exit
            // closes stdout and is reported with what it wrote on stderr.
        }
    }
}

/// Lock-guarded state for the ready handshake: stdout buffer, stderr, and
/// the once-only resume of the awaiting continuation.
private final class ReadyHandshake: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrTail = ""
    private var resumed = false
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    func attach(stdout: FileHandle, stderr: FileHandle) {
        lock.lock()
        stdoutHandle = stdout
        stderrHandle = stderr
        lock.unlock()
    }

    /// Buffers stdout; returns the first complete line once it arrives.
    func appendOutput(_ data: Data) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        stdoutBuffer.append(data)
        guard let newline = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        var line = Data(stdoutBuffer[..<newline])
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        return line
    }

    /// The backend's stderr, kept whole so a failure is said with all of it.
    func appendError(_ text: String) {
        lock.lock()
        stderrTail += text
        lock.unlock()
    }

    /// The captured stderr, formatted as a trailing sentence fragment.
    func stderrSuffix() -> String {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : " " + trimmed
    }

    /// Runs `body` exactly once, detaching both read handlers.
    func finish(_ body: () -> Void) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        let stdout = stdoutHandle
        let stderr = stderrHandle
        lock.unlock()
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        body()
    }
}

enum SpisBackendError: LocalizedError {
    case notInstalled
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return SpisExecutableMissing().errorDescription
        case .failedToStart(let cause):
            return "Spis could not start: \(cause)"
        }
    }

    /// Whether the failure is a missing or incomplete install — our
    /// deployment, never a process that ran and died.
    var isMissingInstall: Bool {
        switch self {
        case .notInstalled:
            return true
        case .failedToStart:
            return false
        }
    }
}
