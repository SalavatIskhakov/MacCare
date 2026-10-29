import SwiftUI
import AppKit
import Foundation
import MachO

private enum InterfaceLanguage {
    static var initial: String {
        Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en" : "ru"
    }
}

enum AppLocalization {
    static var language: String {
        UserDefaults.standard.string(forKey: "interfaceLanguage") ?? InterfaceLanguage.initial
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return String(format: key, locale: Locale(identifier: language), arguments: arguments)
        }
        let localizedFormat = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: localizedFormat, locale: Locale(identifier: language), arguments: arguments)
    }
}

@main
struct MacCareApp: App {
    @StateObject private var model = CareModel()
    @AppStorage("interfaceLanguage") private var interfaceLanguage = InterfaceLanguage.initial

    init() {
        // Set the running Dock icon explicitly as well as shipping AppIcon in
        // the asset catalog. This keeps the Dock icon correct when Launch
        // Services has a stale or missing registration for a locally built app.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: interfaceLanguage))
                .frame(minWidth: 980, minHeight: 650)
                .task { await model.monitorResources() }
        }
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings {
            SettingsView()
                .environment(\.locale, Locale(identifier: interfaceLanguage))
        }
    }
}

enum CareSection: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case cleanup = "Очистка"
    case applications = "Приложения"
    case disk = "Анализ диска"
    case monitor = "Мониторинг"
    case optimize = "Оптимизация"
    case history = "История"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "house"
        case .cleanup: "sparkles"
        case .applications: "square.stack.3d.up"
        case .disk: "internaldrive"
        case .monitor: "waveform.path"
        case .optimize: "gearshape.2"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum MoleCleanupCategory: String, CaseIterable, Identifiable {
    case all, system, essentials, app_caches, browsers, cloud_office, developer, apps
    case virtualization, support, leftovers, apple_silicon, backups, time_machine, large_files, projects

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все категории"
        case .system: "Система"
        case .essentials: "Основные файлы пользователя"
        case .app_caches: "Кэши приложений"
        case .browsers: "Браузеры"
        case .cloud_office: "Облако и офисные приложения"
        case .developer: "Инструменты разработчика"
        case .apps: "Приложения и утилиты"
        case .virtualization: "Виртуализация"
        case .support: "Данные поддержки приложений"
        case .leftovers: "Остатки удалённых приложений"
        case .apple_silicon: "Apple Silicon"
        case .backups: "Резервные копии устройств и прошивки"
        case .time_machine: "Time Machine"
        case .large_files: "Крупные файлы"
        case .projects: "Артефакты проектов"
        }
    }
}

struct MoleCleanupEntry: Identifiable {
    let path: String
    let size: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct MoleCleanupGroup: Identifiable {
    let name: String
    let entries: [MoleCleanupEntry]
    var id: String { name }
}

struct MoleCleanupPreviewDocument {
    let groups: [MoleCleanupGroup]
    let totalSize: String?
    let itemCount: Int
    let categoryCount: Int
    var canRunCleanup: Bool { itemCount > 0 && !groups.isEmpty }

    init(_ text: String) {
        var category = "Другие файлы"
        var categoryOrder: [String] = []
        var entriesByCategory: [String: [MoleCleanupEntry]] = [:]
        var parsedTotal: String?
        var parsedCount: Int?
        var parsedCategoryCount: Int?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                let sourceName = String(line.dropFirst(4).dropLast(4))
                category = Self.localizedCategory(sourceName)
                if entriesByCategory[category] == nil { categoryOrder.append(category) }
                continue
            }
            if line.hasPrefix("# Potential cleanup:") {
                parsedTotal = line.replacingOccurrences(of: "# Potential cleanup:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("# Items:") {
                parsedCount = Int(line.replacingOccurrences(of: "# Items:", with: "").trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix("# Categories:") {
                parsedCategoryCount = Int(line.replacingOccurrences(of: "# Categories:", with: "").trimmingCharacters(in: .whitespaces))
                continue
            }
            guard line.hasPrefix("/"), let separator = line.range(of: " # ", options: .backwards) else { continue }
            let path = String(line[..<separator.lowerBound])
            let size = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !size.isEmpty else { continue }
            if entriesByCategory[category] == nil { categoryOrder.append(category) }
            entriesByCategory[category, default: []].append(MoleCleanupEntry(path: path, size: size))
        }

        groups = categoryOrder.compactMap { name in
            guard let entries = entriesByCategory[name], !entries.isEmpty else { return nil }
            return MoleCleanupGroup(name: name, entries: entries)
        }
        totalSize = parsedTotal
        itemCount = parsedCount ?? groups.reduce(0) { $0 + $1.entries.count }
        categoryCount = parsedCategoryCount ?? groups.count
    }

    private static func localizedCategory(_ category: String) -> String {
        switch category {
        case "User essentials": "Файлы пользователя"
        case "App caches": "Кэши приложений"
        case "Developer tools": "Инструменты разработчика"
        case "Application Support": "Данные приложений"
        default: category
        }
    }
}

struct InstalledApp: Identifiable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
    let source: String
    let uninstallName: String
    let size: String
    var id: String { url.path }
}

struct MoleUninstallPreviewFile: Identifiable {
    let path: String
    let size: String?
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct MoleUninstallPreviewDocument {
    let totalSize: String?
    let files: [MoleUninstallPreviewFile]
    let warning: String?

    init(_ text: String) {
        let plainText = text.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        var parsedTotal: String?
        var parsedFiles: [MoleUninstallPreviewFile] = []
        var parsedWarning: String?
        for rawLine in plainText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.localizedCaseInsensitiveContains("leftover scan timed out") {
                parsedWarning = "Не удалось завершить поиск связанных файлов. В список попало только само приложение."
            }
            if line.hasPrefix("◎ "), !line.contains("Matched"), let comma = line.range(of: " , ", options: .backwards) {
                parsedTotal = String(line[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("✓ ") else { continue }
            let value = String(line.dropFirst(2))
            if let comma = value.range(of: " , ", options: .backwards) {
                parsedFiles.append(MoleUninstallPreviewFile(
                    path: String(value[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces),
                    size: String(value[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
                ))
            } else {
                parsedFiles.append(MoleUninstallPreviewFile(path: value, size: nil))
            }
        }
        totalSize = parsedTotal
        files = parsedFiles
        warning = parsedWarning
    }
}

struct MoleHistorySession: Identifiable {
    let id = UUID()
    let command: String
    let startedAt: String
    let endedAt: String
    let items: Int
    let size: String
    let removed: Int
    let trashed: Int
    let skipped: Int
    let failed: Int
    let failedTasks: Int
}

struct MoleHistoryDeletion: Identifiable {
    let id = UUID()
    let timestamp: String
    let mode: String
    let status: String
    let size: String
    let path: String
}

struct OptimizationReportLine: Identifiable {
    let id: Int
    let text: String
    let kind: Kind

    enum Kind: Equatable { case heading, success, warning, neutral }
    var symbol: String {
        switch kind {
        case .heading: "list.bullet"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .neutral: "circle"
        }
    }
    var tint: Color {
        switch kind {
        case .heading: .blue
        case .success: .green
        case .warning: .orange
        case .neutral: .secondary
        }
    }
}

struct OptimizationReport {
    let title: String
    let details: [OptimizationReportLine]
    let actionableCount: Int
    let error: String?

    init(_ rawText: String) {
        let clean = Self.stripANSI(rawText)
        let lines = clean.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        error = clean.hasPrefix("Mole ") || clean.localizedCaseInsensitiveContains("error:") ? clean : nil
        title = lines.first(where: { $0.localizedCaseInsensitiveContains("optimization complete") || $0.localizedCaseInsensitiveContains("dry run complete") }) ?? "План обслуживания"
        let actionable = lines.first(where: { $0.localizedCaseInsensitiveContains("would apply") })
            .flatMap { $0.split(whereSeparator: { !$0.isNumber }).first }
        let isDryRun = clean.localizedCaseInsensitiveContains("dry run mode")
        let visibleLines = lines.filter { line in
            !line.localizedCaseInsensitiveContains("dry run mode") &&
            !line.localizedCaseInsensitiveContains("performance diagnosis") &&
            line.lowercased() != "optimize" &&
            !line.localizedCaseInsensitiveContains("likely bottleneck") &&
            !line.localizedCaseInsensitiveContains("desktop composition is busy") &&
            !line.hasPrefix("⚙ System") &&
            !line.localizedCaseInsensitiveContains("optimization complete") &&
            !line.localizedCaseInsensitiveContains("dry run complete")
        }
        details = visibleLines.enumerated().map { index, line in
            let lower = line.lowercased()
            let kind: OptimizationReportLine.Kind =
                line.hasPrefix("➤") ? .heading :
                lower.contains("failed") || lower.contains("skipped") || lower.contains("warning") || lower.contains("attention") || lower.contains("unavailable") ? .warning :
                lower.contains("would apply") || lower.contains("applied") || lower.contains("complete") || line.hasPrefix("✓") || line.hasPrefix("→") && !lower.contains("already") && !lower.contains("verified") && !lower.contains("valid") && !lower.contains("no ") ? .success : .neutral
            let displayText = line.replacingOccurrences(of: #"^[→➤⚙✓]\s*"#, with: "", options: .regularExpression)
            return OptimizationReportLine(id: index, text: displayText, kind: kind)
        }
        if let actionable {
            actionableCount = Int(actionable) ?? 0
        } else if isDryRun {
            actionableCount = details.filter { $0.kind == .success }.count
        } else {
            actionableCount = 0
        }
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}

@MainActor
final class CareModel: ObservableObject {
    @Published var selection: CareSection = .overview
    @Published var apps: [InstalledApp] = []
    @Published var isLoadingApps = false
    @Published var applicationSearch = ""
    @Published var launchCategory: MoleCleanupCategory = .all
    @Published var historyScope: HistoryScope = .operations
    @Published var cpuUsage: Double?
    @Published var memoryUsed: UInt64?
    @Published var memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published var moleAvailable = BundledMoleService.isAvailable
    @Published var moleStatus: MoleStatusSummary?
    @Published var moleError: String?
    @Published var diskEntries: [MoleAnalysisEntry] = []
    @Published var diskAnalysisError: String?
    @Published var isDiskAnalyzing = false
    @Published var moleHistorySessions: [MoleHistorySession] = []
    @Published var moleHistoryDeletions: [MoleHistoryDeletion] = []
    @Published var moleHistoryError: String?
    @Published private(set) var didLoadHistory = false
    @Published private(set) var isLoadingHistory = false
    @Published var isMoleCleanScanning = false
    @Published var moleCleanPreview: String?
    @Published var moleCleanPreviewCategory: MoleCleanupCategory?
    @Published var moleCleanupCategory: MoleCleanupCategory = .all
    @Published var moleCleanupError: String?
    @Published var isMoleCleaning = false
    @Published var confirmMoleClean = false
    @Published var moleCleanupResult: String?
    @Published var moleOptimizationPreview: String?
    @Published var moleOptimizationResult: String?
    @Published var isMoleOptimizing = false
    @Published var confirmMoleOptimize = false
    @Published var uninstallPreview: String?
    @Published var uninstallPreviewError: String?
    @Published var isUninstallPreviewLoading = false
    @Published var pendingUninstall: InstalledApp?
    @Published var completedUninstallApp: InstalledApp?
    @Published var confirmUninstall = false
    @Published var isUninstalling = false
    @Published var uninstallResult: String?
    @Published var uninstallResultDetails: String?
    @Published var showUninstallMoleDetails = false
    @Published var isUninstallPreviewSheetPresented = false

    private var previousCPUTicks: [UInt32]?

    var volume: (total: Int64, free: Int64, used: Int64) {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        return (total, free, max(0, total - free))
    }

    var computerName: String { Host.current().localizedName ?? "Mac" }
    var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }
    func loadApplications() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task.detached(priority: .utility) { [weak self] in
            let found: [InstalledApp]
            let loadError: String?
            if BundledMoleService.isAvailable {
                do { found = try await BundledMoleService.applicationInventory(); loadError = nil }
                catch { found = []; loadError = error.localizedDescription }
            } else {
                found = Self.installedApplications()
                loadError = MoleServiceError.engineMissing.localizedDescription
            }
            guard let owner = self else { return }
            await MainActor.run {
                owner.apps = found
                owner.isLoadingApps = false
                owner.moleError = loadError
            }
        }
    }

    func open(_ app: InstalledApp) { NSWorkspace.shared.open(app.url) }
    func reveal(_ app: InstalledApp) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }

    func monitorResources() async {
        while !Task.isCancelled {
            refreshMemory()
            refreshCPU()
            if moleAvailable {
                do {
                    let snapshot = try await BundledMoleService.status()
                    moleStatus = snapshot
                    moleError = nil
                } catch {
                    moleStatus = nil
                    moleError = "Расширенная сводка недоступна; продолжается мониторинг через macOS."
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func loadMoleDiskAnalysis() {
        guard !isDiskAnalyzing else { return }
        isDiskAnalyzing = true
        diskAnalysisError = nil
        Task {
            do { diskEntries = try await BundledMoleService.analyzeOverview() }
            catch { diskAnalysisError = error.localizedDescription }
            isDiskAnalyzing = false
        }
    }

    func loadMoleHistory() {
        guard !didLoadHistory, !isLoadingHistory, moleHistoryError == nil, moleAvailable else { return }
        isLoadingHistory = true
        Task {
            do {
                let json = try await BundledMoleService.historyJSON()
                guard let data = json.data(using: .utf8),
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw MoleServiceError.invalidJSON
                }
                let sessionRows = root["sessions"] as? [[String: Any]] ?? []
                let deletionRows = root["deletions"] as? [[String: Any]] ?? []
                moleHistorySessions = sessionRows.map { row in
                    let actions = row["actions"] as? [String: Any] ?? [:]
                    return MoleHistorySession(
                        command: row["command"] as? String ?? "Операция",
                        startedAt: row["started_at"] as? String ?? "",
                        endedAt: row["ended_at"] as? String ?? "",
                        items: row["items"] as? Int ?? 0,
                        size: row["size"] as? String ?? "—",
                        removed: actions["removed"] as? Int ?? 0,
                        trashed: actions["trashed"] as? Int ?? 0,
                        skipped: actions["skipped"] as? Int ?? 0,
                        failed: actions["failed"] as? Int ?? 0,
                        failedTasks: row["failed_tasks"] as? Int ?? 0
                    )
                }
                moleHistoryDeletions = deletionRows.map { row in
                    let size = row["size_kb"] as? Int
                    return MoleHistoryDeletion(
                        timestamp: row["timestamp"] as? String ?? "",
                        mode: row["mode"] as? String ?? "—",
                        status: row["status"] as? String ?? "—",
                        size: size.map { ByteCountFormatter.string(fromByteCount: Int64($0) * 1024, countStyle: .file) } ?? "—",
                        path: row["path"] as? String ?? ""
                    )
                }
                moleHistoryError = nil
                didLoadHistory = true
                isLoadingHistory = false
            } catch {
                moleHistoryError = error.localizedDescription
                isLoadingHistory = false
            }
        }
    }

    func refreshMoleHistory() {
        didLoadHistory = false
        moleHistoryError = nil
        isLoadingHistory = false
        loadMoleHistory()
    }

    func previewMoleCleanup() {
        guard !isMoleCleanScanning else { return }
        let selectedCategory = moleCleanupCategory
        isMoleCleanScanning = true
        moleCleanupError = nil
        moleCleanPreview = nil
        moleCleanPreviewCategory = nil
        Task {
            do {
                _ = try await BundledMoleService.run(["clean", "--dry-run"], timeout: 15 * 60, cleanCategory: selectedCategory.rawValue)
                let preview = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mole/clean-list.txt")
                moleCleanPreview = Self.readableMoleText(try String(contentsOf: preview, encoding: .utf8))
                moleCleanPreviewCategory = selectedCategory
            } catch { moleCleanupError = error.localizedDescription }
            isMoleCleanScanning = false
        }
    }

    func runMoleCleanup() async -> String? {
        guard let preview = moleCleanPreview,
              MoleCleanupPreviewDocument(preview).canRunCleanup,
              moleCleanPreviewCategory == moleCleanupCategory,
              !isMoleCleaning else { return "Сначала выполните предпросмотр с найденными элементами." }
        isMoleCleaning = true
        defer { isMoleCleaning = false }
        do {
            _ = try await BundledMoleService.run(["clean"], timeout: 60 * 60, cleanCategory: moleCleanupCategory.rawValue)
            moleCleanPreview = nil
            moleCleanupResult = "Очистка завершена."
            moleCleanPreviewCategory = nil
            return moleCleanupResult
        } catch { return error.localizedDescription }
    }

    func setMoleCleanupCategory(_ category: MoleCleanupCategory) {
        guard moleCleanupCategory != category else { return }
        moleCleanupCategory = category
        moleCleanPreview = nil
        moleCleanPreviewCategory = nil
        moleCleanupResult = nil
    }

    private static func readableMoleText(_ text: String) -> String {
        let cleanText = text.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        let detachedANSI = cleanText.replacingOccurrences(
            of: "\\[(?:[0-9;?]+[A-Za-z]|[A-HJKSTfmn])",
            with: "",
            options: .regularExpression
        )
        // Keep diagnostic output verbatim. Translating only selected lines makes
        // technical logs appear mixed-language and can hide useful detail.
        return detachedANSI
    }

    func previewMoleOptimization() {
        guard !isMoleOptimizing else { return }
        isMoleOptimizing = true
        moleOptimizationPreview = nil
        moleOptimizationResult = nil
        Task {
            do { moleOptimizationPreview = try await BundledMoleService.run(["optimize", "--dry-run"]).standardOutput }
            catch { moleOptimizationPreview = error.localizedDescription }
            isMoleOptimizing = false
        }
    }

    func runMoleOptimization() async -> String? {
        guard let preview = moleOptimizationPreview,
              OptimizationReport(preview).actionableCount > 0,
              !isMoleOptimizing else { return "Сначала проверьте план с доступными задачами." }
        isMoleOptimizing = true
        defer { isMoleOptimizing = false }
        do {
            let result = try await BundledMoleService.run(["optimize"], timeout: 30 * 60)
            moleOptimizationResult = result.standardOutput
            moleOptimizationPreview = nil
            return result.standardOutput
        } catch { return error.localizedDescription }
    }

    func previewUninstall(_ app: InstalledApp) {
        guard !isUninstallPreviewLoading else { return }
        isUninstallPreviewLoading = true
        uninstallPreviewError = nil
        uninstallPreview = nil
        uninstallResult = nil
        uninstallResultDetails = nil
        completedUninstallApp = nil
        showUninstallMoleDetails = false
        pendingUninstall = app
        Task {
            do {
                // Mole asks for confirmation even in dry-run mode; this accepts only the non-mutating preview.
                let output = try await BundledMoleService.run(
                    ["uninstall", "--dry-run", app.uninstallName],
                    timeout: 10 * 60,
                    confirmationInput: Data("y\n".utf8)
                )
                uninstallPreview = Self.readableMoleText(output.standardOutput)
            } catch {
                uninstallPreviewError = AppLocalization.format("%@: %@", app.name, Self.readableMoleText(error.localizedDescription))
            }
            isUninstallPreviewLoading = false
        }
    }

    func clearUninstallPreview() {
        guard !isUninstallPreviewLoading, !isUninstalling else { return }
        isUninstallPreviewSheetPresented = false
        pendingUninstall = nil
        uninstallPreview = nil
        uninstallPreviewError = nil
        uninstallResult = nil
        uninstallResultDetails = nil
        completedUninstallApp = nil
        showUninstallMoleDetails = false
    }

    func uninstallPendingApp() async {
        guard let app = pendingUninstall, uninstallPreview != nil, !isUninstalling else { return }
        isUninstalling = true
        completedUninstallApp = app
        defer { isUninstalling = false }
        do {
            let result = try await BundledMoleService.run(
                ["uninstall", app.uninstallName],
                timeout: 30 * 60,
                confirmationInput: Data("y\n".utf8)
            )
            let output = Self.readableMoleText([result.standardOutput, result.standardError].filter { !$0.isEmpty }.joined(separator: "\n"))
            uninstallResultDetails = output
            if output.localizedCaseInsensitiveContains("Uninstall incomplete") {
                uninstallResult = "Операция завершилась не полностью. Некоторые файлы могли остаться на месте."
            } else if output.localizedCaseInsensitiveContains("No applications were uninstalled.") {
                uninstallResult = "Приложение не перемещено в Корзину. Причина указана в подробном выводе."
            } else if output.localizedCaseInsensitiveContains("Uninstall complete"), output.localizedCaseInsensitiveContains("Removed ") {
                uninstallResult = "Обработка завершена. Приложение и найденные файлы отправлены в Корзину."
            } else {
                uninstallResult = "Команда завершена. Проверьте подробный вывод результата."
            }
            uninstallPreview = nil
            pendingUninstall = nil
            loadApplications()
        } catch {
            uninstallPreviewError = Self.readableMoleText(error.localizedDescription)
        }
    }

    private func refreshMemory() {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = UInt64(vm_page_size)
        let availablePages = UInt64(statistics.free_count + statistics.inactive_count + statistics.speculative_count + statistics.purgeable_count)
        memoryUsed = memoryTotal - min(memoryTotal, availablePages * pageSize)
    }

    private func refreshCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let current = withUnsafeBytes(of: info.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        defer { previousCPUTicks = current }
        guard let previousCPUTicks, previousCPUTicks.count == current.count else { return }
        let deltas = zip(current, previousCPUTicks).map { $0 &- $1 }.map(Double.init)
        let total = deltas.reduce(0, +)
        guard total > 0, deltas.count == 4 else { return }
        cpuUsage = ((deltas[0] + deltas[1] + deltas[2]) / total).clamped(to: 0...1)
    }

    private nonisolated static func installedApplications() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), URL(fileURLWithPath: "/System/Applications", isDirectory: true), URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)]
        var found: [InstalledApp] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for url in children where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                found.append(InstalledApp(url: url, name: name, bundleID: bundle.bundleIdentifier ?? "—", source: "macOS", uninstallName: name, size: "—"))
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

}

struct RootView: View {
    @EnvironmentObject private var model: CareModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image("AppIcon").resizable().scaledToFit().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Mac Care").font(.headline)
                    Spacer()
                }.padding(.horizontal, 16).padding(.vertical, 18)
                List(CareSection.allCases, selection: $model.selection) { section in
                    Label(LocalizedStringKey(section.rawValue), systemImage: section.symbol).tag(section)
                }.listStyle(.sidebar)
                Group {
                    if #available(macOS 14.0, *) {
                        SettingsWindowButton()
                    } else {
                        Button {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        } label: {
                            Label("Настройки", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }.frame(minWidth: 190)
        } detail: {
            Group {
                switch model.selection {
                case .overview: DashboardView()
                case .cleanup: CleanupView()
                case .applications: ApplicationsView().task { model.loadApplications() }
                case .disk: DiskView()
                case .monitor: MonitorView()
                case .optimize: MaintenanceView()
                case .history: HistoryView()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }.navigationSplitViewStyle(.balanced)
    }
}

@available(macOS 14.0, *)
private struct SettingsWindowButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button { openSettings() } label: {
            Label("Настройки", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.buttonStyle(.plain)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: CareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Мой Mac").font(.system(size: 30, weight: .bold))
                    Text("Состояние и обслуживание компьютера").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(model.computerName).fontWeight(.semibold)
                    Text(model.osVersion).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                HStack(spacing: 24) {
                    StorageRing(used: model.volume.used, total: model.volume.total, free: model.volume.free)
                    VStack(alignment: .leading, spacing: 14) {
                        Legend(color: .blue, title: "Используется", value: ByteCountFormatter.string(fromByteCount: model.volume.used, countStyle: .file))
                        Legend(color: .green, title: "Свободно", value: ByteCountFormatter.string(fromByteCount: model.volume.free, countStyle: .file))
                        Text("Том запуска macOS").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(22).frame(maxWidth: .infinity, minHeight: 235).card()
                VStack(spacing: 16) {
                    MetricCard(title: "Процессор", value: model.cpuUsage.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Сбор…", subtitle: "Текущая загрузка CPU", icon: "cpu", tint: .green)
                    MetricCard(title: "Память", value: model.memoryUsed.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "Сбор…", subtitle: AppLocalization.format("из %@", ByteCountFormatter.string(fromByteCount: Int64(model.memoryTotal), countStyle: .memory)), icon: "memorychip", tint: .blue)
                    MetricCard(title: "Последний запуск", value: model.moleHistorySessions.first?.startedAt ?? "Пока не было", subtitle: model.moleHistorySessions.first.map { Self.commandName($0.command) } ?? "Операции обслуживания появятся здесь", icon: "clock", tint: .purple)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Стандартный поиск").font(.headline)
                Text("Покажем найденные элементы во вкладке «Очистка». Поиск ничего не удаляет.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Picker("Тип поиска", selection: $model.launchCategory) {
                        ForEach(MoleCleanupCategory.allCases) { category in Text(LocalizedStringKey(category.title)).tag(category) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 340, alignment: .leading)
                    .disabled(!model.moleAvailable || model.isMoleCleanScanning || model.isMoleCleaning)
                    Spacer()
                    Button {
                        model.setMoleCleanupCategory(model.launchCategory)
                        model.selection = .cleanup
                        model.previewMoleCleanup()
                    } label: {
                        Label("Запустить поиск", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.moleAvailable || model.isMoleCleanScanning || model.isMoleCleaning)
                }
                if !model.moleAvailable {
                    Label(MoleServiceError.engineMissing.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .card()
            Spacer(minLength: 0)
        }
        .task { model.loadMoleHistory() }
    }

    private static func commandName(_ command: String) -> String {
        switch command {
        case "clean": AppLocalization.format("Поиск для очистки")
        case "optimize": AppLocalization.format("Оптимизация")
        case "uninstall": AppLocalization.format("Удаление приложения")
        default: AppLocalization.format(command.capitalized)
        }
    }
}

struct CleanupView: View {
    @EnvironmentObject private var model: CareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Очистка").font(.system(size: 28, weight: .bold))
                    Text("Выберите категорию, проверьте список и только затем запускайте очистку.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.moleAvailable {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Категория", selection: Binding(
                        get: { model.moleCleanupCategory },
                        set: { model.setMoleCleanupCategory($0) }
                    )) {
                        ForEach(MoleCleanupCategory.allCases) { category in Text(LocalizedStringKey(category.title)).tag(category) }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.isMoleCleanScanning || model.isMoleCleaning)
                    HStack {
                        Label("Обслуживающий модуль готов", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Предпросмотр") { model.previewMoleCleanup() }.disabled(model.isMoleCleanScanning || model.isMoleCleaning)
                        if let preview = model.moleCleanPreview,
                           MoleCleanupPreviewDocument(preview).canRunCleanup {
                            Button("Запустить очистку", role: .destructive) { model.confirmMoleClean = true }
                                .disabled(model.isMoleCleaning || model.moleCleanPreviewCategory != model.moleCleanupCategory)
                        }
                    }
                    if let error = model.moleCleanupError { Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).textSelection(.enabled) }
                    if let result = model.moleCleanupResult { Text(LocalizedStringKey(result)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(8) }
                    if model.isMoleCleanScanning {
                        LoadingStateView(title: "Ищем элементы для очистки", detail: "Это безопасная проверка: файлы пока не изменяются.")
                    } else if let preview = model.moleCleanPreview,
                       MoleCleanupPreviewDocument(preview).canRunCleanup {
                        let document = MoleCleanupPreviewDocument(preview)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("План очистки").font(.headline)
                                    Text("Проверьте список элементов перед очисткой.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(document.totalSize ?? "—").font(.title3.bold()).monospacedDigit()
                                    Text(AppLocalization.format("%ld элементов · %ld категорий", document.itemCount, document.categoryCount)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Label("Предпросмотр безопасен: файлы пока не изменены.", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(document.groups) { group in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text(LocalizedStringKey(group.name)).font(.subheadline.weight(.semibold))
                                                Spacer()
                                                Text("\(group.entries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            }
                                            ForEach(group.entries) { entry in
                                                HStack(spacing: 9) {
                                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(entry.name).font(.callout).lineLimit(1)
                                                        Text(entry.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                                                    }
                                                    Spacer(minLength: 8)
                                                    Text(entry.size).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                                }
                                                .padding(.vertical, 3)
                                            }
                                        }
                                    }
                                    if document.groups.isEmpty {
                                        Text("Список пуст или имеет неизвестный формат.")
                                            .font(.callout).foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            .frame(minHeight: 220, maxHeight: .infinity)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .layoutPriority(1)
                    } else if model.moleCleanPreview != nil {
                        EmptyStateView(title: "В этой секции нечего очищать", icon: "checkmark.circle", detail: "Предпросмотр не нашёл файлов для выбранной категории. Запуск очистки недоступен.")
                            .frame(maxHeight: .infinity)
                    } else if model.moleCleanupError == nil {
                        EmptyStateView(title: "Предпросмотр ещё не запускался", icon: "sparkles", detail: "Выберите категорию и нажмите «Предпросмотр». Найденные элементы появятся здесь.")
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .card()
            } else {
                Label("Не найден встроенный обслуживающий модуль. Пересоберите приложение на этом Mac.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).padding(12).card()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Запустить очистку?", isPresented: $model.confirmMoleClean, titleVisibility: .visible) {
            Button("Запустить очистку", role: .destructive) {
                Task { model.moleCleanupResult = await model.runMoleCleanup() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(model.moleCleanupCategory == .all
                 ? AppLocalization.format("Система повторно проверит все категории и очистит разрешённые файлы. Часть действий необратима, включая очистку Корзины.")
                 : AppLocalization.format(
                    "Система повторно проверит категорию «%@». Часть действий может удалять файлы безвозвратно. Сверьте список предпросмотра перед продолжением.",
                    AppLocalization.format(model.moleCleanupCategory.title)
                 ))
        }
    }
}

struct ApplicationsView: View {
    @EnvironmentObject private var model: CareModel
    @AppStorage("interfaceLanguage") private var interfaceLanguage = InterfaceLanguage.initial
    private var filteredApps: [InstalledApp] {
        model.applicationSearch.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(model.applicationSearch) || $0.bundleID.localizedCaseInsensitiveContains(model.applicationSearch) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Приложения").font(.system(size: 28, weight: .bold))
            Text(AppLocalization.format("Найдено установленных приложений: %ld. Инвентарь готов к просмотру.", model.apps.count)).foregroundStyle(.secondary)
                    if let error = model.moleError { Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            TextField("Поиск приложений", text: $model.applicationSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            if model.isLoadingApps {
                LoadingStateView(title: "Сканируем приложения", detail: "Проверяем стандартные папки приложений.")
                    .frame(minHeight: 240)
            }
            else if model.apps.isEmpty { EmptyStateView(title: "Приложения не найдены", icon: "square.stack.3d.up", detail: "Проверьте доступ к стандартным папкам Applications.") }
            else {
                List(filteredApps) { app in
                    HStack(spacing: 12) {
                        AppIconView(url: app.url)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).fontWeight(.medium)
                            Text("\(app.source) · \(app.bundleID)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(app.size).font(.caption).foregroundStyle(.secondary)
                        Button("Показать") { model.reveal(app) }
                        Button("Предпросмотр удаления") {
                            model.previewUninstall(app)
                            model.isUninstallPreviewSheetPresented = true
                        }.disabled(!model.moleAvailable || model.isUninstallPreviewLoading || model.isUninstalling)
                        Button("Открыть") { model.open(app) }.buttonStyle(.borderedProminent).tint(.green)
                    }.padding(.vertical, 3)
                }.listStyle(.inset)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.isUninstallPreviewSheetPresented },
            set: { isPresented in
                guard isPresented || (!model.isUninstallPreviewLoading && !model.isUninstalling) else { return }
                model.isUninstallPreviewSheetPresented = isPresented
            }
        ), onDismiss: model.clearUninstallPreview) {
            UninstallPreviewSheet()
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: interfaceLanguage))
                .frame(minWidth: 620, minHeight: 500)
        }
    }
}

struct UninstallPreviewSheet: View {
    @EnvironmentObject private var model: CareModel
    private var isBusy: Bool { model.isUninstallPreviewLoading || model.isUninstalling }
    private var uninstallFailed: Bool {
        guard let result = model.uninstallResult?.lowercased() else { return false }
        return result.contains("не полностью") || result.contains("не переместил") || result.contains("incomplete") || result.contains("was not moved")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let app = model.pendingUninstall ?? model.completedUninstallApp { AppIconView(url: app.url).frame(width: 48, height: 48) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.uninstallResult == nil ? "План перемещения в Корзину" : "Результат операции").font(.title2.bold())
                    if let app = model.pendingUninstall ?? model.completedUninstallApp {
                        Text(app.name).foregroundStyle(.secondary)
                    } else {
                        Text("Приложение").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let preview = model.uninstallPreview {
                    let document = MoleUninstallPreviewDocument(preview)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(document.totalSize ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
                        Text(AppLocalization.format("в Корзину · %ld объектов", document.files.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if model.isUninstalling {
                LoadingStateView(title: "Перемещаем в Корзину", detail: "Обрабатываем приложение и найденные связанные файлы.")
            } else if model.isUninstallPreviewLoading {
                LoadingStateView(title: "Проверяем приложение", detail: "Ищем связанные файлы. Во время проверки ничего не изменяется.")
            } else if let error = model.uninstallPreviewError {
                Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let preview = model.uninstallPreview {
                let document = MoleUninstallPreviewDocument(preview)
                Label("Предпросмотр безопасен: пока ничего не изменено.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                if let warning = document.warning {
                    Label(LocalizedStringKey(warning), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if model.pendingUninstall?.url.path.hasPrefix("/Applications/") == true {
                    Label("Для приложения в /Applications macOS может запросить пароль администратора. При отказе файлы останутся на месте.", systemImage: "lock")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if document.files.isEmpty {
                    Label("Не удалось распознать список файлов. Проверьте подробный вывод перед удалением.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(document.files) { file in
                            HStack(spacing: 12) {
                                Image(systemName: file.name.hasSuffix(".app") ? "app" : "doc")
                                    .foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                                }
                                Spacer(minLength: 12)
                                Text(file.size ?? "—").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            if file.id != document.files.last?.id { Divider() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: .infinity)

                Button("Показать технические подробности") { model.showUninstallMoleDetails.toggle() }
                    .buttonStyle(.link)
                if model.showUninstallMoleDetails {
                    ScrollView {
                        Text(preview).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    .frame(maxHeight: 110)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if let result = model.uninstallResult {
                VStack(alignment: .leading, spacing: 14) {
                    Label(LocalizedStringKey(result),
                          systemImage: uninstallFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(uninstallFailed ? .orange : .green)
                    Button("Показать подробности") { model.showUninstallMoleDetails.toggle() }
                        .buttonStyle(.link)
                    if model.showUninstallMoleDetails, let details = model.uninstallResultDetails {
                        ScrollView {
                            Text(details).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }
                        .frame(maxHeight: 220)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button("Закрыть") { model.clearUninstallPreview() }
                    .disabled(isBusy)
                    .keyboardShortcut(.cancelAction)
                if model.uninstallPreview != nil {
                    Button("Переместить в Корзину…", role: .destructive) { model.confirmUninstall = true }
                        .disabled(model.isUninstalling || model.pendingUninstall == nil || MoleUninstallPreviewDocument(model.uninstallPreview ?? "").files.isEmpty)
                }
            }
        }
        .padding(22)
        .interactiveDismissDisabled(isBusy)
        .confirmationDialog("Переместить приложение в Корзину?", isPresented: $model.confirmUninstall, titleVisibility: .visible) {
            Button("Переместить в Корзину", role: .destructive) { Task { await model.uninstallPendingApp() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(AppLocalization.format("Система повторно проверит %@ и переместит найденные файлы в Корзину.", model.pendingUninstall?.name ?? AppLocalization.format("Приложение")))
        }
    }
}

struct AppIconView: View {
    let url: URL
    var body: some View {
        Group {
            if let image = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 34, height: 34)
            }
        }.frame(width: 36, height: 36)
    }
}

struct DiskView: View {
    @EnvironmentObject private var model: CareModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Анализ диска").font(.system(size: 28, weight: .bold))
            Text("Анализ занятого места на диске.").foregroundStyle(.secondary)
            HStack { Button("Сканировать диск") { model.loadMoleDiskAnalysis() }.disabled(model.isDiskAnalyzing) }
            if let error = model.diskAnalysisError { Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            if model.isDiskAnalyzing {
                LoadingStateView(title: "Анализируем диск", detail: "Собираем размеры папок и файлов.")
                    .frame(minHeight: 240)
            } else if model.diskEntries.isEmpty {
                EmptyStateView(title: "Анализ не запускался", icon: "chart.treemap", detail: model.moleAvailable ? "Запустите сканирование диска." : "Встроенный модуль анализа недоступен.")
            } else {
                List(model.diskEntries) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(entry.isDirectory ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name).fontWeight(.medium)
                            Text(entry.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).font(.callout.monospacedDigit())
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) } label: { Image(systemName: "magnifyingglass") }.help("Показать в Finder")
                    }.padding(.vertical, 2)
                }.listStyle(.inset)
            }
            Spacer()
        }.task { if model.diskEntries.isEmpty { model.loadMoleDiskAnalysis() } }
    }
}

struct MonitorView: View {
    @EnvironmentObject private var model: CareModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Мониторинг").font(.system(size: 28, weight: .bold))
            Text("Показатели CPU и памяти обновляются каждые 2 секунды средствами macOS. Дополнительная сводка показывается, если модуль доступен.").foregroundStyle(.secondary)
            if let score = model.moleStatus?.healthScore { Label(AppLocalization.format("Индекс здоровья: %ld/100", score), systemImage: "heart.text.square.fill").font(.headline).foregroundStyle(.green) }
            if let error = model.moleError { Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack(spacing: 16) {
                MetricCard(title: "Загрузка CPU", value: model.cpuUsage.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Сбор…", subtitle: "Все процессорные ядра", icon: "cpu", tint: .green)
                MetricCard(title: "Используется памяти", value: model.memoryUsed.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "Сбор…", subtitle: "Из физической памяти", icon: "memorychip", tint: .blue)
                MetricCard(title: "Физическая память", value: ByteCountFormatter.string(fromByteCount: Int64(model.memoryTotal), countStyle: .memory), subtitle: "Объём устройства", icon: "memorychip.fill", tint: .purple)
            }
            Spacer()
        }
    }
}

struct MaintenanceView: View {
    @EnvironmentObject private var model: CareModel
    private var preview: OptimizationReport? { model.moleOptimizationPreview.map(OptimizationReport.init) }
    private var result: OptimizationReport? { model.moleOptimizationResult.map(OptimizationReport.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Оптимизация").font(.system(size: 28, weight: .bold))
                Text("Проверьте план обслуживания macOS, затем решите, применять ли его.").foregroundStyle(.secondary)
            }
            if model.moleAvailable {
                HStack(spacing: 10) {
                    Button { model.previewMoleOptimization() } label: {
                        Label("Составить план", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isMoleOptimizing)
                    if preview?.actionableCount ?? 0 > 0 {
                        Button(role: .destructive) { model.confirmMoleOptimize = true } label: {
                            Label("Применить план", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isMoleOptimizing)
                    }
                    Spacer()
                }
                if model.isMoleOptimizing {
                    LoadingStateView(
                        title: model.moleOptimizationPreview == nil ? "Составляем план" : "Выполняем оптимизацию",
                        detail: "Пожалуйста, подождите."
                    )
                } else if let report = preview {
                    OptimizationReportCard(report: report, isPreview: true)
                } else if !model.isMoleOptimizing, model.moleOptimizationResult == nil {
                    EmptyStateView(title: "План ещё не составлен", icon: "slider.horizontal.3", detail: "Нажмите «Составить план». Проверка не меняет настройки Mac.")
                        .frame(maxHeight: .infinity)
                }
                if let report = result { OptimizationReportCard(report: report, isPreview: false) }
            } else {
                EmptyStateView(title: "Обслуживающий модуль недоступен", icon: "exclamationmark.triangle", detail: MoleServiceError.engineMissing.localizedDescription)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Применить план оптимизации?", isPresented: $model.confirmMoleOptimize, titleVisibility: .visible) {
            Button("Выполнить оптимизацию") { Task { model.moleOptimizationResult = await model.runMoleOptimization() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут выполнены задачи из проверенного плана. Отдельные действия могут потребовать права администратора или быть пропущены.")
        }
    }
}

private struct OptimizationReportCard: View {
    let report: OptimizationReport
    let isPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(isPreview ? "План обслуживания" : "Результат оптимизации", systemImage: isPreview ? "list.bullet.clipboard" : "checkmark.seal")
                    .font(.headline)
                Spacer()
                if isPreview {
                    Text(AppLocalization.format("%ld задач к выполнению", report.actionableCount))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(report.actionableCount > 0 ? .green : .secondary)
                }
            }
            if isPreview {
                Label("Пока ничего не изменено. Запуск выполняется отдельно.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = report.error {
                Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            if report.details.isEmpty && report.error == nil {
                EmptyStateView(title: "Нет задач для показа", icon: "checkmark.circle", detail: "Для этого запуска дополнительных действий нет.")
            } else {
                List(report.details) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol).foregroundStyle(item.tint).padding(.top, 2)
                        Text(item.text)
                            .fontWeight(item.kind == .heading ? .semibold : .regular)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
                .frame(minHeight: 180, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

enum HistoryScope: String, CaseIterable, Identifiable {
    case operations = "Запуски"
    case deletions = "Изменения файлов"
    var id: String { rawValue }
}

struct HistoryView: View {
    @EnvironmentObject private var model: CareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("История").font(.system(size: 28, weight: .bold))
                    Text("Запуски обслуживания и действия с файлами на этом Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refreshMoleHistory() } label: { Label("Обновить", systemImage: "arrow.clockwise") }
                    .disabled(!model.moleAvailable || model.isLoadingHistory)
            }
            if !model.moleAvailable {
                EmptyStateView(title: "История недоступна", icon: "exclamationmark.triangle", detail: MoleServiceError.engineMissing.localizedDescription)
            } else if let error = model.moleHistoryError {
                EmptyStateView(title: "Не удалось загрузить историю", icon: "exclamationmark.triangle", detail: error)
            } else if !model.didLoadHistory {
                LoadingStateView(title: "Загружаем историю", detail: "Собираем список предыдущих операций.")
            } else {
                HStack(spacing: 12) {
                    MetricCard(title: "Запуски", value: "\(model.moleHistorySessions.count)", subtitle: "операции обслуживания", icon: "terminal", tint: .blue)
                    MetricCard(title: "Удалено", value: "\(model.moleHistorySessions.reduce(0) { $0 + $1.removed })", subtitle: "элементов по журналу", icon: "trash", tint: .orange)
                    MetricCard(title: "Ошибки", value: "\(model.moleHistorySessions.reduce(0) { $0 + $1.failed + $1.failedTasks })", subtitle: "неудачные действия", icon: "exclamationmark.circle", tint: .purple)
                }
                Picker("История", selection: $model.historyScope) {
                    ForEach(HistoryScope.allCases) { item in Text(LocalizedStringKey(item.rawValue)).tag(item) }
                }
                .pickerStyle(.segmented)
                if model.historyScope == .operations {
                    if model.moleHistorySessions.isEmpty {
                        EmptyStateView(title: "Запусков пока нет", icon: "clock.arrow.circlepath", detail: "Запуски поиска, очистки и оптимизации появятся здесь.")
                    } else {
                        List(model.moleHistorySessions) { session in
                            HistorySessionRow(session: session)
                        }
                        .listStyle(.inset)
                    }
                } else if model.moleHistoryDeletions.isEmpty {
                    EmptyStateView(title: "Подробный журнал файлов пуст", icon: "doc.text.magnifyingglass", detail: "Сводные итоги запусков отображаются во вкладке «Запуски». Для этого периода подробные записи по отдельным файлам отсутствуют.")
                } else {
                    List(model.moleHistoryDeletions) { deletion in
                        HistoryDeletionRow(deletion: deletion)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { model.loadMoleHistory() }
    }
}

private struct HistorySessionRow: View {
    let session: MoleHistorySession
    private var symbol: String {
        switch session.command {
        case "clean": "sparkles"
        case "optimize": "gearshape.2"
        case "uninstall": "trash"
        default: "terminal"
        }
    }
    private var title: String {
        switch session.command {
        case "clean": "Поиск / очистка"
        case "optimize": "Оптимизация"
        case "uninstall": "Удаление приложения"
        default: session.command.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.blue).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).fontWeight(.semibold)
                Text(session.startedAt).font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.format("%ld элементов · удалено %ld · пропущено %ld · ошибок %ld", session.items, session.removed, session.skipped, session.failed + session.failedTasks))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.size).font(.callout.monospacedDigit())
        }
        .padding(.vertical, 5)
    }
}

private struct HistoryDeletionRow: View {
    let deletion: MoleHistoryDeletion
    private var tint: Color { deletion.status == "ok" ? .green : (deletion.status.contains("fail") ? .red : .secondary) }
    private var localizedStatus: String {
        switch deletion.status.lowercased() {
        case "ok", "success": "Успешно"
        case "failed", "fail", "error": "Ошибка"
        case "skipped", "skip": "Пропущено"
        default: "Неизвестно"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deletion.status == "ok" ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(LocalizedStringKey(localizedStatus)).fontWeight(.medium)
                    Text(LocalizedStringKey(deletion.mode.capitalized)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(deletion.size).font(.callout.monospacedDigit())
                }
                Text(deletion.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                Text(deletion.timestamp).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = InterfaceLanguage.initial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac Care").font(.title2.bold())
                        Text("Настройки и сведения о приложении").foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeading(title: "Язык интерфейса", symbol: "globe")
                    Picker("Язык интерфейса", selection: $interfaceLanguage) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeading(title: "Работа с файлами", symbol: "doc.text.magnifyingglass")
                    Text("Стандартный поиск показывает найденные элементы и сам ничего не удаляет.")
                    Text("Очистка запускается отдельно. Перед подтверждением проверьте список: некоторые действия могут удалять данные без помещения в Корзину.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeading(title: "Совместимость", symbol: "desktopcomputer")
                    LabeledContent("Система", value: "macOS 13 или новее")
                    LabeledContent("Процессор", value: "Apple Silicon")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("О программе").font(.headline)
                    Text("Mac Care · предварительная сборка").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 620, height: 500, alignment: .topLeading)
    }
}

private struct SettingsSectionHeading: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            Text(LocalizedStringKey(title)).font(.headline)
        }
    }
}

struct StorageRing: View {
    let used: Int64
    let total: Int64
    let free: Int64
    private var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.green.opacity(0.15), lineWidth: 14)
            Circle().trim(from: 0, to: ratio).stroke(AngularGradient(colors: [.blue, .green, .green], center: .center), style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)).font(.system(size: 24, weight: .bold, design: .rounded))
                Text("свободно").font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.format("из %@", ByteCountFormatter.string(fromByteCount: total, countStyle: .file))).font(.caption2).foregroundStyle(.tertiary)
            }
        }.frame(width: 155, height: 155).accessibilityLabel(AppLocalization.format("Свободно %@", ByteCountFormatter.string(fromByteCount: free, countStyle: .file)))
    }
}

struct Legend: View {
    let color: Color
    let title: String
    let value: String
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout).fontWeight(.semibold)
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3).frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold())
                Text(LocalizedStringKey(subtitle)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct EmptyStateView: View {
    let title: String
    let icon: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(LocalizedStringKey(title)).font(.headline)
            Text(LocalizedStringKey(detail)).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}

struct LoadingStateView: View {
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(LocalizedStringKey(title))
                .font(.headline)
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func card() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.05)))
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
