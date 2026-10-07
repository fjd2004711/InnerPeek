import Foundation

/// One line of `pluginkit -m -A -D -i <identifier> -v`.
struct ExtensionRegistration: Equatable, Sendable {
    /// `+` elected, `-` ignored, `=` superseded, `!` debug, `?` unknown, `nil` default.
    let election: Character?
    let identifier: String
    let version: String
    let path: String

    var isIgnored: Bool { election == "-" }

    /// The `.app` that contains this extension, used to clean up its LaunchServices record.
    var appPath: String? {
        guard let range = path.range(of: "/Contents/PlugIns/") else { return nil }
        return String(path[..<range.lowerBound])
    }
}

enum ExtensionHealth: Equatable, Sendable {
    /// Registered at the installed location, enabled, and nothing stale.
    case healthy
    /// Nothing is registered at all.
    case notRegistered
    /// This copy is not the registered one; another location is.
    case registeredElsewhere
    /// Registered but switched off in System Settings.
    case disabled
    /// Healthy, but records point at files that no longer exist or at another copy of the app.
    case needsCleanup(stale: Int, otherCopies: Int)
}

struct RepairCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    var display: String { ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ") }
}

enum ExtensionDiagnostics {
    static let pluginKit = "/usr/bin/pluginkit"
    static let quickLookManager = "/usr/bin/qlmanage"
    static let launchServicesRegister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    static let extensionIdentifier = "com.innerpeek.InnerPeek.QuickLook"

    static func parse(_ output: String) -> [ExtensionRegistration] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 4, let path = columns.last, path.hasPrefix("/") else { return nil }
            let head = columns[0]
            guard let open = head.firstIndex(of: "("), let close = head.lastIndex(of: ")"), open < close else { return nil }
            let leading = head[..<open].trimmingCharacters(in: .whitespaces)
            let election = leading.first.flatMap { "+-!=?".contains($0) ? $0 : nil }
            let identifier = leading.drop { "+-!=? ".contains($0) }
            guard !identifier.isEmpty else { return nil }
            return ExtensionRegistration(election: election, identifier: String(identifier),
                                         version: String(head[head.index(after: open)..<close]), path: path)
        }
    }

    /// App bundles named InnerPeek*.app that LaunchServices still has records for, from
    /// `lsregister -dump | grep '^path:.*InnerPeek'`. Mounted volumes are ignored because
    /// those records cannot be removed and disappear on their own.
    static func parseLaunchServices(_ output: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("path:") {
            var path = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let marker = path.range(of: " (0x", options: .backwards) { path = String(path[..<marker.lowerBound]) }
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard path.hasPrefix("/"), name.hasPrefix("InnerPeek"), name.hasSuffix(".app"), !path.hasPrefix("/Volumes/"),
                  seen.insert(path).inserted else { continue }
            result.append(path)
        }
        return result
    }

    /// A record is stale when its file is gone or sits in the Trash. Only the record is removed;
    /// the file itself is never touched.
    private static func isStale(_ path: String, _ fileExists: (String) -> Bool) -> Bool {
        path.contains("/.Trash/") || !fileExists(path)
    }

    static func health(of registrations: [ExtensionRegistration], installedExtensionPath: String,
                       launchServicesApps: [String] = [],
                       fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> ExtensionHealth {
        guard let current = registrations.first(where: { $0.path == installedExtensionPath }) else {
            return registrations.isEmpty ? .notRegistered : .registeredElsewhere
        }
        if current.isIgnored { return .disabled }
        let others = registrations.filter { $0.path != installedExtensionPath }
        let installedApp = current.appPath
        var staleApps = Set(others.filter { isStale($0.path, fileExists) }.compactMap { $0.appPath ?? $0.path })
        staleApps.formUnion(launchServicesApps.filter { $0 != installedApp && isStale($0, fileExists) })
        let copies = others.filter { !isStale($0.path, fileExists) }.count
        return staleApps.isEmpty && copies == 0 ? .healthy : .needsCleanup(stale: staleApps.count, otherCopies: copies)
    }

    /// Commands that remove records of files that no longer exist, register the installed
    /// extension, enable it and reset the Quick Look caches. Existing copies elsewhere are
    /// never touched, so a second install the user keeps on purpose survives.
    static func repairPlan(registrations: [ExtensionRegistration], installedExtensionPath: String,
                           launchServicesApps: [String] = [],
                           fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [RepairCommand] {
        var plan: [RepairCommand] = []
        var seenApps = Set<String>()
        for registration in registrations where registration.path != installedExtensionPath && isStale(registration.path, fileExists) {
            plan.append(RepairCommand(executable: pluginKit, arguments: ["-r", registration.path]))
            if let app = registration.appPath, isStale(app, fileExists), seenApps.insert(app).inserted {
                plan.append(RepairCommand(executable: launchServicesRegister, arguments: ["-u", app]))
            }
        }
        let installedApp = registrations.first { $0.path == installedExtensionPath }?.appPath
        for app in launchServicesApps where app != installedApp && isStale(app, fileExists) && seenApps.insert(app).inserted {
            plan.append(RepairCommand(executable: launchServicesRegister, arguments: ["-u", app]))
        }
        plan.append(RepairCommand(executable: pluginKit, arguments: ["-a", installedExtensionPath]))
        plan.append(RepairCommand(executable: pluginKit, arguments: ["-e", "use", "-i", extensionIdentifier]))
        plan.append(RepairCommand(executable: quickLookManager, arguments: ["-r"]))
        plan.append(RepairCommand(executable: quickLookManager, arguments: ["-r", "cache"]))
        return plan
    }

    /// A report that is safe to paste into an issue: no file contents, and the home folder is shortened to `~`.
    static func report(appVersion: String, systemVersion: String, architecture: String, appPath: String,
                       registrations: [ExtensionRegistration], health: ExtensionHealth,
                       fullDiskAccess: Bool, settings: PreviewSettings, homeDirectory: String) -> String {
        func shorten(_ path: String) -> String { homeDirectory.isEmpty ? path : path.replacingOccurrences(of: homeDirectory, with: "~") }
        func describe(_ health: ExtensionHealth) -> String {
            switch health {
            case .healthy: return "healthy"
            case .notRegistered: return "not registered"
            case .registeredElsewhere: return "registered at another location"
            case .disabled: return "disabled in System Settings"
            case let .needsCleanup(stale, copies): return "needs cleanup (\(stale) stale, \(copies) other copies)"
            }
        }
        var lines = [
            "InnerPeek \(appVersion)",
            "macOS \(systemVersion) (\(architecture))",
            "App: \(shorten(appPath))",
            "Quick Look extension: \(describe(health))",
            "Full Disk Access: \(fullDiskAccess ? "granted" : "not detected")",
            "Registrations (\(registrations.count)):"
        ]
        for registration in registrations {
            lines.append("  \(registration.election.map(String.init) ?? " ") \(registration.version)  \(shorten(registration.path))")
        }
        lines.append("Settings: language=\(settings.language.rawValue) depth=\(settings.scanDepth) entries=\(settings.maximumEntries) "
                     + "summary=\(settings.showSummary) insights=\(settings.showInsights) techStack=\(settings.showTechStack) "
                     + "brandIcons=\(settings.showBrandIcons) hidden=\(settings.showHiddenFiles) icons=\(settings.iconStyle.rawValue)")
        return lines.joined(separator: "\n")
    }
}
