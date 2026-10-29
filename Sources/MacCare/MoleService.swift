import Foundation

struct MoleCommandOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}

struct MoleStatusSummary: Sendable {
    let host: String
    let healthScore: Int?
    let cpuUsage: Double?
    let memoryUsed: UInt64?
    let memoryTotal: UInt64?
    let memoryPressure: String?
    let disks: [MoleDiskSummary]
}

struct MoleDiskSummary: Sendable, Identifiable {
    let mount: String
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    var id: String { mount }
}

struct MoleAnalysisEntry: Sendable, Identifiable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    var id: String { path }
}

enum MoleServiceError: LocalizedError {
    case engineMissing
    case unsupportedCommand
    case processLaunch(String)
    case commandFailed(Int32, String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .engineMissing: AppLocalization.format("В этой сборке не найден встроенный обслуживающий модуль. Пересоберите приложение на этом Mac.")
        case .unsupportedCommand: AppLocalization.format("Команда не разрешена сервисом Mac Care.")
        case .processLaunch(let details): AppLocalization.format("Не удалось запустить обслуживающую операцию: %@", details)
        case .commandFailed(let status, let details): AppLocalization.format("Операция завершилась с кодом %d: %@", status, details)
        case .invalidJSON: AppLocalization.format("Обслуживающий модуль вернул данные в неизвестном формате.")
        }
    }
}

/// Runs only the fixed, bundled Mole entrypoint. Arguments are passed as an
/// argv array; no user-provided shell command is constructed or evaluated.
enum BundledMoleService {
    private static let allowedCommands: Set<String> = ["status", "analyze", "history", "uninstall", "clean", "optimize", "purge", "installer", "slim"]
    private static let allowedCleanCategories: Set<String> = ["all", "system", "essentials", "app_caches", "browsers", "cloud_office", "developer", "apps", "virtualization", "support", "leftovers", "apple_silicon", "backups", "time_machine", "large_files", "projects"]

    static var engineRoot: URL? {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        return nil
        #endif
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Mole/\(architecture)", isDirectory: true),
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("mole").path),
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/analyze-go").path),
              FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/status-go").path) else { return nil }
        return root
    }

    static var isAvailable: Bool { engineRoot != nil }

    static func run(_ arguments: [String], timeout: TimeInterval = 90, confirmationInput: Data? = nil, cleanCategory: String? = nil) async throws -> MoleCommandOutput {
        guard let root = engineRoot else { throw MoleServiceError.engineMissing }
        guard let command = arguments.first, allowedCommands.contains(command) else { throw MoleServiceError.unsupportedCommand }
        guard cleanCategory == nil || (command == "clean" && cleanCategory.map(allowedCleanCategories.contains) == true) else { throw MoleServiceError.unsupportedCommand }

        return try await Task.detached(priority: .utility) {
            try runSynchronously(arguments, root: root, timeout: timeout, confirmationInput: confirmationInput, cleanCategory: cleanCategory)
        }.value
    }

    private static func runSynchronously(_ arguments: [String], root: URL, timeout: TimeInterval, confirmationInput: Data?, cleanCategory: String?) throws -> MoleCommandOutput {
            let process = Process()
            let command = arguments.first ?? ""
            if ["clean", "optimize", "uninstall"].contains(command) {
                do {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Mac Care/Mole", isDirectory: true),
                        withIntermediateDirectories: true
                    )
                    if command == "clean" {
                        try FileManager.default.createDirectory(
                            at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mole", isDirectory: true),
                            withIntermediateDirectories: true
                        )
                    }
                } catch {
                    throw MoleServiceError.processLaunch(AppLocalization.format("Не удалось подготовить пользовательские каталоги: %@", error.localizedDescription))
                }
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: root.appendingPathComponent("mole").path)
            process.arguments = arguments
            process.currentDirectoryURL = root
            let input = confirmationInput == nil ? nil : Pipe()
            process.standardInput = input.map { $0 as Any } ?? FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "LC_ALL": "C",
                "LANG": "C",
                "TERM": "dumb",
                "MOLE_NO_UPDATE_CHECK": "1",
                "MOLE_LOG_FILE": NSHomeDirectory() + "/Library/Logs/Mac Care/Mole/mole.log",
                "MOLE_OPERATIONS_LOG": NSHomeDirectory() + "/Library/Logs/Mac Care/Mole/operations.log",
                "MOLE_DELETE_LOG": NSHomeDirectory() + "/Library/Logs/Mac Care/Mole/deletions.log",
                "MOLE_DEBUG_LOG_FILE": NSHomeDirectory() + "/Library/Logs/Mac Care/Mole/debug.log"
            ]
            if let cleanCategory { process.environment?["MOLE_CLEAN_CATEGORY"] = cleanCategory }

            let outputQueue = DispatchQueue(label: "com.maccare.mole.output")
            var stdoutData = Data()
            var stderrData = Data()
            let readers = DispatchGroup()
            readers.enter()
            outputQueue.async {
                stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
            readers.enter()
            outputQueue.async {
                stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }

            do { try process.run() }
            catch { throw MoleServiceError.processLaunch(error.localizedDescription) }
            if let confirmationInput, let input {
                input.fileHandleForWriting.write(confirmationInput)
                try? input.fileHandleForWriting.close()
            }

            let deadline = DispatchTime.now() + timeout
            let exited = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                exited.signal()
            }
            if exited.wait(timeout: deadline) == .timedOut {
                process.terminate()
                _ = exited.wait(timeout: .now() + 2)
                throw MoleServiceError.processLaunch("превышено время ожидания")
            }
            readers.wait()
            let result = MoleCommandOutput(
                standardOutput: String(decoding: stdoutData, as: UTF8.self),
                standardError: String(decoding: stderrData, as: UTF8.self),
                exitCode: process.terminationStatus
            )
            guard result.exitCode == 0 else {
                let details = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                let output = details.isEmpty ? result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) : details
                throw MoleServiceError.commandFailed(result.exitCode, output)
            }
            return result
    }

    static func status() async throws -> MoleStatusSummary {
        let output = try await run(["status", "--json"])
        guard let data = output.standardOutput.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MoleServiceError.invalidJSON }
        let cpu = root["cpu"] as? [String: Any]
        let memory = root["memory"] as? [String: Any]
        let disks = (root["disks"] as? [[String: Any]] ?? []).compactMap { item -> MoleDiskSummary? in
            guard let mount = item["mount"] as? String else { return nil }
            return MoleDiskSummary(mount: mount, used: (item["used"] as? NSNumber)?.uint64Value ?? 0,
                                   total: (item["total"] as? NSNumber)?.uint64Value ?? 0,
                                   usedPercent: (item["used_percent"] as? NSNumber)?.doubleValue ?? 0)
        }
        return MoleStatusSummary(
            host: root["host"] as? String ?? "Mac",
            healthScore: (root["health_score"] as? NSNumber)?.intValue,
            cpuUsage: (cpu?["usage"] as? NSNumber)?.doubleValue,
            memoryUsed: (memory?["used"] as? NSNumber)?.uint64Value,
            memoryTotal: (memory?["total"] as? NSNumber)?.uint64Value,
            memoryPressure: memory?["pressure"] as? String,
            disks: disks
        )
    }

    static func analyzeOverview() async throws -> [MoleAnalysisEntry] {
        let output = try await run(["analyze", "--json"], timeout: 10 * 60)
        guard let data = output.standardOutput.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else { throw MoleServiceError.invalidJSON }
        return entries.compactMap { item in
            guard let path = item["path"] as? String else { return nil }
            return MoleAnalysisEntry(name: item["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                                     path: path, size: (item["size"] as? NSNumber)?.int64Value ?? 0,
                                     isDirectory: item["is_dir"] as? Bool ?? false)
        }.sorted { $0.size > $1.size }
    }

    static func applicationInventory() async throws -> [InstalledApp] {
        let output = try await run(["uninstall", "--list"], timeout: 5 * 60)
        guard let data = output.standardOutput.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MoleServiceError.invalidJSON }
        return rows.compactMap { row in
            guard let path = row["path"] as? String else { return nil }
            return InstalledApp(url: URL(fileURLWithPath: path),
                                name: row["name"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                bundleID: row["bundle_id"] as? String ?? "—",
                                source: row["source"] as? String ?? "—",
                                uninstallName: row["uninstall_name"] as? String ?? row["name"] as? String ?? "",
                                size: row["size"] as? String ?? "—")
        }
    }

    static func historyJSON() async throws -> String {
        let output = try await run(["history", "--json"])
        guard let data = output.standardOutput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { throw MoleServiceError.invalidJSON }
        return String(decoding: pretty, as: UTF8.self)
    }
}
