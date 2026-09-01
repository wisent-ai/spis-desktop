import Foundation

/// Crawl command execution methods on SpisClient.
/// These methods invoke the `spis crawl` CLI commands as external processes
/// with concurrent pipe draining and proper error handling.
extension SpisClient {
    
    // MARK: - Crawl operations (spis crawl start/status/resume/import)
    
    func crawlStart(config: CrawlerStartConfig, workingDirectory: URL? = nil) async throws -> CrawlOperation {
        let output = try await runCrawlProcess(args: config.buildArguments(), workingDirectory: workingDirectory)
        guard output.succeeded else {
            throw NSError(domain: "CrawlOperation", code: Int(output.exitCode), userInfo: [
                NSLocalizedDescriptionKey: output.error ?? "Crawl start failed"
            ])
        }
        return try decodeCrawlOperation(output.stdout)
    }
    
    func crawlStatus(runId: String, record: String? = nil, workingDirectory: URL? = nil) async throws -> CrawlOperation {
        var args = ["crawl", "status", "--run", runId]
        if let record = record {
            args.append("--record")
            args.append(record)
        }
        let output = try await runCrawlProcess(args: args, workingDirectory: workingDirectory)
        guard output.succeeded else {
            throw NSError(domain: "CrawlOperation", code: Int(output.exitCode), userInfo: [
                NSLocalizedDescriptionKey: output.error ?? "Crawl status failed"
            ])
        }
        return try decodeCrawlOperation(output.stdout)
    }
    
    func crawlResume(runId: String, workingDirectory: URL? = nil) async throws -> CrawlOperation {
        let output = try await runCrawlProcess(args: ["crawl", "resume", "--run", runId], workingDirectory: workingDirectory)
        guard output.succeeded else {
            throw NSError(domain: "CrawlOperation", code: Int(output.exitCode), userInfo: [
                NSLocalizedDescriptionKey: output.error ?? "Crawl resume failed"
            ])
        }
        return try decodeCrawlOperation(output.stdout)
    }
    
    func crawlImport(runId: String, workingDirectory: URL? = nil) async throws -> CrawlOperation {
        let output = try await runCrawlProcess(args: ["crawl", "import", "--run", runId], workingDirectory: workingDirectory)
        guard output.succeeded else {
            throw NSError(domain: "CrawlOperation", code: Int(output.exitCode), userInfo: [
                NSLocalizedDescriptionKey: output.error ?? "Crawl import failed"
            ])
        }
        return try decodeCrawlOperation(output.stdout)
    }
    
    // MARK: - Crawl process execution (concurrent pipe draining)
    
    /// Runs a `spis crawl` CLI command as a subprocess, draining stdout/stderr concurrently.
    /// ProcessResult includes exit code and both output streams.
    private func runCrawlProcess(args: [String], workingDirectory: URL? = nil) async throws -> ProcessResult {
        let process = Process()
        guard let spisBinary = locateSpisBinary(from: workingDirectory) else {
            throw NSError(domain: "CrawlOperation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not locate spis binary. Ensure 'spis' is installed in PATH or accessible from the repository."
            ])
        }
        
        process.executableURL = URL(fileURLWithPath: spisBinary)
        process.arguments = args
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Start reading both pipes immediately in detached tasks (before process.run) to prevent deadlock on large output
        let stdoutTask = Task.detached { () -> Data in
            (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        let stderrTask = Task.detached { () -> Data in
            (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        
        // Run process and wait for termination in detached task to avoid blocking
        let processTask = Task.detached { () -> ProcessResult in
            try process.run()
            process.waitUntilExit()
            
            // Get data from pipe readers
            let stdoutData = await stdoutTask.value
            let stderrData = await stderrTask.value
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }
        
        do {
            return try await processTask.value
        } catch {
            // Cleanup on failure
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }
    }
    
    private func decodeCrawlOperation(_ json: String) throws -> CrawlOperation {
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "CrawlOperation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not encode JSON response to UTF-8"
            ])
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CrawlOperation.self, from: data)
    }
    
    /// Locates the `spis` binary in standard search paths and repository checkouts.
    private func locateSpisBinary(from workingDirectory: URL?) -> String? {
        // If workingDirectory is provided, look for spis in its release subdirectory
        if let workingDirectory = workingDirectory {
            let releaseSpis = workingDirectory.appendingPathComponent("target/release/spis").path
            if FileManager.default.fileExists(atPath: releaseSpis) {
                return releaseSpis
            }
        }
        
        // Standard search paths
        let candidates = [
            "/usr/local/bin/spis",
            "/usr/bin/spis",
            "/opt/homebrew/bin/spis",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.local/bin/spis",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.cargo/bin/spis",
        ]
        
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Search PATH directories
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            let pathDirs = pathEnv.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
            for dir in pathDirs {
                let candidate = dir + "/spis"
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }
        
        // Try to find in repository checkout relative to executable location
        let fm = FileManager.default
        let bundlePath = Bundle.main.executablePath ?? ""
        let possibleRepos = [
            fm.currentDirectoryPath + "/target/release/spis",
            URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path + "/spis",
            URL(fileURLWithPath: bundlePath).deletingLastPathComponent().deletingLastPathComponent().path + "/target/release/spis",
        ]
        
        for path in possibleRepos {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
}
