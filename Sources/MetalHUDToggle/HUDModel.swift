import Foundation
import SwiftUI
import ServiceManagement

// MARK: - Process helpers

enum Shell {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = URL(fileURLWithPath: path).lastPathComponent
            throw Failure(message: "\(name) failed (exit code \(process.terminationStatus)). \(detail)")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Launchctl {
    static func set(_ key: String, _ value: String) throws {
        try Shell.run("/bin/launchctl", ["setenv", key, value])
    }

    static func unset(_ key: String) throws {
        try Shell.run("/bin/launchctl", ["unsetenv", key])
    }

    static func get(_ key: String) -> String? {
        guard let value = try? Shell.run("/bin/launchctl", ["getenv", key]), !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Model

final class HUDModel: ObservableObject {
    /// Every variable this app may set (used to clean up when the HUD is turned off).
    static let managedKeys = [
        "MTL_HUD_ENABLED",
        "MTL_HUD_ELEMENTS",
        "MTL_HUD_ALIGNMENT",
        "MTL_HUD_SCALE",
        "MTL_HUD_OPACITY",
        "MTL_HUD_LOG_ENABLED",
        "MTL_HUD_LOGGING_ENABLED",
        "MTL_HUD_LOG_SHADER_ENABLED",
    ]

    private let defaults = UserDefaults.standard
    private var pendingApply: DispatchWorkItem?
    private var isSyncingLoginItem = false

    // Master switch
    @Published var enabled: Bool {
        didSet { if enabled != oldValue { commit() } }
    }

    // Metrics
    @Published var elements: Set<HUDElement> {
        didSet { if elements != oldValue { commit() } }
    }

    // Appearance
    @Published var overrideAlignment: Bool {
        didSet { if overrideAlignment != oldValue { commit() } }
    }
    @Published var alignment: HUDAlignment {
        didSet { if alignment != oldValue { commit() } }
    }
    @Published var overrideScale: Bool {
        didSet { if overrideScale != oldValue { commit() } }
    }
    @Published var scale: Double {
        didSet { if scale != oldValue { commit() } }
    }
    @Published var overrideOpacity: Bool {
        didSet { if overrideOpacity != oldValue { commit() } }
    }
    @Published var opacity: Double {
        didSet { if opacity != oldValue { commit() } }
    }

    // Logging
    @Published var logFrames: Bool {
        didSet { if logFrames != oldValue { commit() } }
    }
    @Published var logShaders: Bool {
        didSet { if logShaders != oldValue { commit() } }
    }

    // Startup
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !isSyncingLoginItem else { return }
            updateLoginItem(previous: oldValue)
        }
    }
    @Published var enableHUDAtLogin: Bool {
        didSet {
            guard enableHUDAtLogin != oldValue else { return }
            defaults.set(enableHUDAtLogin, forKey: "enableHUDAtLogin")
            // "Start with HUD on" implies "Start at login".
            if enableHUDAtLogin && !launchAtLogin { launchAtLogin = true }
        }
    }

    @Published var errorMessage: String?

    init() {
        let autoEnable = defaults.bool(forKey: "enableHUDAtLogin")

        enabled = autoEnable || Launchctl.get("MTL_HUD_ENABLED") == "1"

        if let saved = defaults.stringArray(forKey: "elements") {
            elements = Set(saved.compactMap(HUDElement.init(rawValue:)))
        } else {
            elements = HUDElement.defaultSelection
        }

        overrideAlignment = defaults.bool(forKey: "overrideAlignment")
        alignment = HUDAlignment(rawValue: defaults.string(forKey: "alignment") ?? "") ?? .topright
        overrideScale = defaults.bool(forKey: "overrideScale")
        scale = defaults.object(forKey: "scale") as? Double ?? 0.2
        overrideOpacity = defaults.bool(forKey: "overrideOpacity")
        opacity = defaults.object(forKey: "opacity") as? Double ?? 1.0

        logFrames = defaults.bool(forKey: "logFrames")
        logShaders = defaults.bool(forKey: "logShaders")

        launchAtLogin = SMAppService.mainApp.status == .enabled
        enableHUDAtLogin = autoEnable

        // Property observers don't fire inside init, so apply explicitly.
        if autoEnable {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
    }

    // MARK: Helpers for the UI

    func binding(for element: HUDElement) -> Binding<Bool> {
        Binding(
            get: { self.elements.contains(element) },
            set: { isOn in
                if isOn { self.elements.insert(element) } else { self.elements.remove(element) }
            }
        )
    }

    func activeCount(in group: HUDGroup) -> Int {
        elements.filter { $0.group == group }.count
    }

    // MARK: Environment variables

    private var desiredEnvironment: [(String, String)] {
        var env: [(String, String)] = [("MTL_HUD_ENABLED", "1")]

        if !elements.isEmpty {
            let ordered = HUDElement.allCases.filter { elements.contains($0) }.map(\.rawValue)
            env.append(("MTL_HUD_ELEMENTS", ordered.joined(separator: ",")))
        }
        if overrideAlignment {
            env.append(("MTL_HUD_ALIGNMENT", alignment.rawValue))
        }
        if overrideScale {
            env.append(("MTL_HUD_SCALE", String(format: "%.2f", scale)))
        }
        if overrideOpacity {
            env.append(("MTL_HUD_OPACITY", String(format: "%.2f", opacity)))
        }
        if logFrames {
            // Apple's docs mention both names; setting both is harmless.
            env.append(("MTL_HUD_LOG_ENABLED", "1"))
            env.append(("MTL_HUD_LOGGING_ENABLED", "1"))
        }
        if logShaders {
            env.append(("MTL_HUD_LOG_SHADER_ENABLED", "1"))
        }
        return env
    }

    private func commit() {
        save()
        // Debounce so dragging a slider doesn't spawn a burst of launchctl calls.
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func save() {
        defaults.set(elements.map(\.rawValue), forKey: "elements")
        defaults.set(overrideAlignment, forKey: "overrideAlignment")
        defaults.set(alignment.rawValue, forKey: "alignment")
        defaults.set(overrideScale, forKey: "overrideScale")
        defaults.set(scale, forKey: "scale")
        defaults.set(overrideOpacity, forKey: "overrideOpacity")
        defaults.set(opacity, forKey: "opacity")
        defaults.set(logFrames, forKey: "logFrames")
        defaults.set(logShaders, forKey: "logShaders")
    }

    private func apply() {
        let env = enabled ? desiredEnvironment : []
        let active = Set(env.map { $0.0 })

        do {
            for key in Self.managedKeys where !active.contains(key) {
                try Launchctl.unset(key)
            }
            for (key, value) in env {
                try Launchctl.set(key, value)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Login item

    private func updateLoginItem(previous: Bool) {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    errorMessage = "Approve the app in System Settings → General → Login Items."
                } else {
                    errorMessage = nil
                }
            } else {
                try SMAppService.mainApp.unregister()
                errorMessage = nil
                // "Start with HUD on" makes no sense without "Start at login".
                if enableHUDAtLogin { enableHUDAtLogin = false }
            }
        } catch {
            errorMessage = "Couldn't update the login item: \(error.localizedDescription)"
            isSyncingLoginItem = true
            launchAtLogin = previous
            isSyncingLoginItem = false
            if !launchAtLogin { enableHUDAtLogin = false }
        }
    }
}
