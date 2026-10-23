import Foundation

/// The one place the app looks for the `spis` command-line core, in order:
/// the checkout `REFERENCE_ENGINE_ROOT` names, a checkout above this app (or
/// its `spis` sibling), `~/.stado/bin/spis` where `stado product install spis
/// --surface cli` puts it, then every directory on `PATH`. Both the loopback
/// backend and the crawl operations run what this finds, so they never
/// disagree about which `spis` is installed.
struct SpisExecutable {
    /// The executable to run.
    let url: URL
    /// The directory it runs in: its checkout when it was found in one, else
    /// the user's home directory.
    let workingDirectory: URL

    /// The command that installs the core where the app finds it.
    static let installCommand = "stado product install spis --surface cli"

    /// Every place `locate` looked, nearest first, for a refusal to name.
    static func searchedPlaces() -> [String] {
        let repository = CorpusRepository()
        var places: [String] = []
        if let root = repository.root {
            places += CorpusRepository.BuildProfile.allCases.map {
                root.appendingPathComponent($0.executablePath).path
            }
        }
        places.append("target/{release,debug}/spis of a checkout above this app")
        places.append(installedPath.path)
        places.append("spis on PATH (\(pathEnvironment))")
        return places
    }

    static func locate() -> SpisExecutable? {
        let repository = CorpusRepository()
        if let root = repository.locateProductRoot(),
            let url = repository.spisExecutable(in: root)
        {
            return SpisExecutable(url: url, workingDirectory: root)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if FileManager.default.isExecutableFile(atPath: installedPath.path) {
            return SpisExecutable(url: installedPath, workingDirectory: home)
        }
        for directory in pathEnvironment.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("spis")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return SpisExecutable(url: candidate, workingDirectory: home)
            }
        }
        return nil
    }

    private static var installedPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".stado/bin/spis")
    }

    private static var pathEnvironment: String {
        ProcessInfo.processInfo.environment["PATH"] ?? ""
    }
}

/// No `spis` core was found where the app looks for it.
struct SpisExecutableMissing: LocalizedError {
    var errorDescription: String? {
        """
        Spis Desktop could not find the spis command-line core. It looked in: \
        \(SpisExecutable.searchedPlaces().joined(separator: "; ")). \
        Install it with `\(SpisExecutable.installCommand)`, or set REFERENCE_ENGINE_ROOT \
        to a spis checkout built with `cargo build --release`, then reopen the app.
        """
    }
}
