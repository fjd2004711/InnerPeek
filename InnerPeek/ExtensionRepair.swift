import Foundation
import AppKit

/// Runs the small, fixed set of system tools the diagnostics need. The app is not
/// sandboxed, so it can ask the system about and repair its own extension registration.
enum CommandRunner {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() } catch {
                    continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

@MainActor
final class ExtensionStatusModel: ObservableObject {
    @Published private(set) var registrations: [ExtensionRegistration] = []
    @Published private(set) var health: ExtensionHealth = .notRegistered
    @Published private(set) var isBusy = false
    @Published private(set) var log: [String] = []
    @Published private(set) var loaded = false
    private var launchServicesApps: [String] = []

    /// Where this running copy of the extension lives.
    var installedExtensionPath: String {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("InnerPeekQL.appex").path ?? ""
    }

    func refresh() async {
        let result = await CommandRunner.run(ExtensionDiagnostics.pluginKit, ["-m", "-A", "-D", "-i", ExtensionDiagnostics.extensionIdentifier, "-v"])
        registrations = ExtensionDiagnostics.parse(result.output)
        // The pluginkit list hides records of deleted apps, but LaunchServices keeps them and they
        // can make Finder fall back to its default card, so they are checked separately.
        let records = await CommandRunner.run("/bin/sh", ["-c", "\(ExtensionDiagnostics.launchServicesRegister) -dump 2>/dev/null | /usr/bin/grep -E '^path:.*InnerPeek'"], timeout: 60)
        launchServicesApps = ExtensionDiagnostics.parseLaunchServices(records.output)
        health = ExtensionDiagnostics.health(of: registrations, installedExtensionPath: installedExtensionPath, launchServicesApps: launchServicesApps)
        loaded = true
    }

    /// Cleans stale records, registers this copy, resets Quick Look and optionally restarts Finder.
    func repair(restartFinder: Bool, language: (String, String) -> String) async {
        guard !isBusy else { return }
        isBusy = true
        log = []
        let plan = ExtensionDiagnostics.repairPlan(registrations: registrations, installedExtensionPath: installedExtensionPath, launchServicesApps: launchServicesApps)
        for command in plan {
            let result = await CommandRunner.run(command.executable, command.arguments)
            log.append((result.succeeded ? "✓ " : "✗ ") + command.display)
        }
        if restartFinder {
            let result = await CommandRunner.run("/usr/bin/killall", ["Finder", "QuickLookUIService"])
            log.append((result.succeeded ? "✓ " : "✗ ") + language("已重启 Finder 与 Quick Look 服务", "Restarted Finder and the Quick Look service"))
        }
        await refresh()
        isBusy = false
    }

    func copyDiagnostics(fullDiskAccess: Bool, settings: PreviewSettings) {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let report = ExtensionDiagnostics.report(
            appVersion: version, systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture,
            appPath: Bundle.main.bundleURL.path, registrations: registrations, health: health,
            fullDiskAccess: fullDiskAccess, settings: settings, homeDirectory: NSHomeDirectory()
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

enum FullDiskAccess {
    /// Full Disk Access cannot be queried directly; reading a protected folder is the standard probe.
    static func isGranted() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Library/Mail", "Library/Safari", "Library/Messages"].contains { location in
            (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(location), includingPropertiesForKeys: nil)) != nil
        }
    }
}
