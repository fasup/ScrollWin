import AppKit
import ApplicationServices
import Foundation

// MARK: - Constants

enum DefaultsKey {
    static let reverseMouseScrollEnabled = "reverseMouseScrollEnabled"
    static let launchAtLoginEnabled      = "launchAtLoginEnabled"
    static let statusIconStyle           = "statusIconStyle"
}

enum DaemonState {
    case stopped
    case running
    case failedToStart   // daemon binary missing or agent failed to load
}

enum StatusIconStyle: String, CaseIterable {
    case minimalWheel
    case splitScroll
    case arrowReverse

    var title: String {
        switch self {
        case .minimalWheel: return "Icon Style: Minimal Wheel"
        case .splitScroll:  return "Icon Style: Split Scroll"
        case .arrowReverse: return "Icon Style: Arrow Reverse"
        }
    }
}

// MARK: - ScrollInverter

/// Controls the scroll-inversion daemon by managing a per-user LaunchAgent.
/// The daemon binary is launched BY launchd (not as a child of this app), so
/// macOS grants it Accessibility trust automatically — no TCC entry needed.
@MainActor
final class ScrollInverter {
    static let shared = ScrollInverter()

    // LaunchAgent identity for the daemon (separate from the app's own agent)
    private let daemonLabel   = "com.scrollwin.daemon"
    private var daemonPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(daemonLabel).plist")
    }
    private var daemonBinURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin/scrollwin-daemon")
    }

    private(set) var state: DaemonState = .stopped
    private var wantsEnabled = false

    var desiredEnabled: Bool { wantsEnabled }
    var isRunning: Bool { state == .running }

    func setEnabled(_ enabled: Bool) {
        wantsEnabled = enabled
        enabled ? start() : stop()
    }

    // MARK: start / stop

    private func start() {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: daemonBinURL.path) else {
            state = .failedToStart; return
        }
        do {
            try writeDaemonPlist()
            launchctl("load", daemonPlistURL.path)
            state = .running
        } catch {
            state = .failedToStart
        }
    }

    private func stop() {
        launchctl("unload", daemonPlistURL.path)
        try? FileManager.default.removeItem(at: daemonPlistURL)
        state = .stopped
    }

    // MARK: helpers

    private func writeDaemonPlist() throws {
        let dir = daemonPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label":            daemonLabel,
            "ProgramArguments": [daemonBinURL.path],
            "RunAtLoad":        true,
            "KeepAlive":        true,   // launchd auto-restarts if daemon crashes
            "ProcessType":      "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: daemonPlistURL, options: .atomic)
    }

    @discardableResult
    private func launchctl(_ verb: String, _ path: String) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = [verb, path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }

    func retryIfNeeded() {
        guard wantsEnabled else { return }
        // If plist is gone (e.g. removed externally) re-install it
        if !FileManager.default.fileExists(atPath: daemonPlistURL.path) {
            isRunning ? (state = .stopped) : ()
        }
        if !isRunning { start() }
    }
}

// MARK: - LaunchAgentManager  (manages the APP's login-item agent)

@MainActor
final class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private let fileManager = FileManager.default
    private var agentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.codex.scrollmousewin.plist")
    }

    func isEnabled() -> Bool { fileManager.fileExists(atPath: agentURL.path) }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try install() } else { try uninstall() }
    }

    private func install() throws {
        let exe = Bundle.main.executableURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ScrollMouseWin")
        let dir = agentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label":            "com.codex.scrollmousewin",
            "ProgramArguments": [exe.path],
            "RunAtLoad":        true,
            "KeepAlive":        false,
            "ProcessType":      "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
    }

    private func uninstall() throws {
        guard isEnabled() else { return }
        try fileManager.removeItem(at: agentURL)
    }
}

// MARK: - StatusMenuController

@MainActor
final class StatusMenuController: NSObject {
    private let defaults   = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu       = NSMenu()
    private let toggleItem = NSMenuItem()
    private let launchItem = NSMenuItem()
    private let infoItem   = NSMenuItem()
    private let accessibilityItem = NSMenuItem()
    private let iconStyleItem = NSMenuItem()
    private var retryTimer: Timer?

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
        removeLegacyAgents()
        applySavedState()
        startRetryTimer()
    }

    // MARK: Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.image = makeStatusIcon(for: currentIconStyle())
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = "ScrollWin"
            button.setAccessibilityLabel("ScrollWin")
        }
        statusItem.menu = menu
    }

    private func currentIconStyle() -> StatusIconStyle {
        if let rawValue = defaults.string(forKey: DefaultsKey.statusIconStyle),
           let style = StatusIconStyle(rawValue: rawValue) {
            return style
        }
        return .splitScroll
    }

    private func refreshStatusIcon() {
        statusItem.button?.image = makeStatusIcon(for: currentIconStyle())
    }

    private func makeStatusIcon(for style: StatusIconStyle) -> NSImage {
        switch style {
        case .minimalWheel:
            return makeMinimalWheelIcon()
        case .splitScroll:
            return makeSplitScrollIcon()
        case .arrowReverse:
            return makeArrowReverseIcon()
        }
    }

    private func makeMinimalWheelIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()

        let bodyRect = NSRect(x: 4.5, y: 1.5, width: 9, height: 14)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 4.5, yRadius: 4.5)
        NSColor.labelColor.setStroke()
        bodyPath.lineWidth = 1.6
        bodyPath.stroke()

        let seamPath = NSBezierPath()
        seamPath.move(to: NSPoint(x: size.width / 2, y: 9.8))
        seamPath.line(to: NSPoint(x: size.width / 2, y: 14.2))
        seamPath.lineWidth = 1.2
        seamPath.stroke()

        let wheelRect = NSRect(x: 7.15, y: 7.0, width: 3.7, height: 4.5)
        let wheelPath = NSBezierPath(roundedRect: wheelRect, xRadius: 1.8, yRadius: 1.8)
        NSColor.systemRed.setFill()
        wheelPath.fill()

        image.unlockFocus()
        return image
    }

    private func makeSplitScrollIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()

        let bodyRect = NSRect(x: 4.2, y: 1.3, width: 11.0, height: 16.4)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 5.2, yRadius: 5.2)
        NSColor.labelColor.setStroke()
        bodyPath.lineWidth = 1.65
        bodyPath.stroke()

        let seamPath = NSBezierPath()
        seamPath.move(to: NSPoint(x: size.width / 2, y: 10.4))
        seamPath.line(to: NSPoint(x: size.width / 2, y: 15.7))
        seamPath.lineWidth = 1.15
        seamPath.stroke()

        NSColor.systemRed.setFill()
        for index in 0..<3 {
            let rect = NSRect(x: 8.8, y: 5.4 + CGFloat(index) * 2.55, width: 2.45, height: 1.6)
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
        }

        image.unlockFocus()
        return image
    }

    private func makeArrowReverseIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()

        let bodyRect = NSRect(x: 5.2, y: 2.1, width: 7.9, height: 13.0)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 4.0, yRadius: 4.0)
        NSColor.labelColor.setStroke()
        bodyPath.lineWidth = 1.45
        bodyPath.stroke()

        let seamPath = NSBezierPath()
        seamPath.move(to: NSPoint(x: size.width / 2, y: 9.9))
        seamPath.line(to: NSPoint(x: size.width / 2, y: 13.6))
        seamPath.lineWidth = 1.0
        seamPath.stroke()

        let wheelRect = NSRect(x: 7.55, y: 7.0, width: 2.9, height: 3.7)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: wheelRect, xRadius: 1.4, yRadius: 1.4).fill()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 4.1, y: 8.3))
        arrow.curve(to: NSPoint(x: 12.2, y: 5.2),
                    controlPoint1: NSPoint(x: 4.4, y: 4.7),
                    controlPoint2: NSPoint(x: 9.5, y: 3.7))
        NSColor.systemRed.setStroke()
        arrow.lineWidth = 1.45
        arrow.lineCapStyle = .round
        arrow.stroke()

        let arrowHead = NSBezierPath()
        arrowHead.move(to: NSPoint(x: 11.2, y: 3.9))
        arrowHead.line(to: NSPoint(x: 13.4, y: 5.3))
        arrowHead.line(to: NSPoint(x: 11.1, y: 6.5))
        arrowHead.lineWidth = 1.45
        arrowHead.lineCapStyle = .round
        arrowHead.lineJoinStyle = .round
        arrowHead.stroke()

        image.unlockFocus()
        return image
    }

    private func configureMenu() {
        toggleItem.target = self
        toggleItem.action = #selector(toggleReverseScroll)
        menu.addItem(toggleItem)

        launchItem.target = self
        launchItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchItem)

        infoItem.isEnabled = false
        menu.addItem(infoItem)

        let iconSubmenu = NSMenu()
        for style in StatusIconStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            iconSubmenu.addItem(item)
        }
        iconStyleItem.title = "Icon Style"
        iconStyleItem.submenu = iconSubmenu
        menu.addItem(iconStyleItem)

        accessibilityItem.title = "Open Accessibility Settings"
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Remove the old manually-created daemon agent (com.scrollwin.daemon.plist).
    /// ScrollInverter now uses com.codex.scrollmousewin.daemon.plist instead.
    private func removeLegacyAgents() {
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.scrollwin.daemon.plist")
        if FileManager.default.fileExists(atPath: legacy.path) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = ["unload", legacy.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError  = FileHandle.nullDevice
            try? proc.run(); proc.waitUntilExit()
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    private func applySavedState() {
        let enabled = defaults.object(forKey: DefaultsKey.reverseMouseScrollEnabled) as? Bool ?? true
        ScrollInverter.shared.setEnabled(enabled)
        updateToggleItem()

        let launchEnabled = defaults.bool(forKey: DefaultsKey.launchAtLoginEnabled)
                         || LaunchAgentManager.shared.isEnabled()
        defaults.set(launchEnabled, forKey: DefaultsKey.launchAtLoginEnabled)
        updateLaunchItem()
        updateInfoItem()
        updateIconMenu()
    }

    // MARK: Update UI

    private func updateToggleItem() {
        let on = ScrollInverter.shared.desiredEnabled
        toggleItem.title = on ? "Reverse Mouse Scroll: On" : "Reverse Mouse Scroll: Off"
        toggleItem.state = on ? .on : .off
        updateInfoItem()
    }

    private func updateLaunchItem() {
        let on = defaults.bool(forKey: DefaultsKey.launchAtLoginEnabled)
        launchItem.title = on ? "Launch at Login: On" : "Launch at Login: Off"
        launchItem.state = on ? .on : .off
    }

    private func updateInfoItem() {
        switch ScrollInverter.shared.state {
        case .running:      infoItem.title = "Mouse wheel direction is reversed ✓"
        case .stopped:      infoItem.title = "Mouse wheel direction is normal"
        case .failedToStart: infoItem.title = "⚠️ Could not start scroll daemon"
        }
    }

    private func updateIconMenu() {
        let selectedStyle = currentIconStyle()
        iconStyleItem.submenu?.items.forEach { item in
            let rawValue = item.representedObject as? String
            item.state = rawValue == selectedStyle.rawValue ? .on : .off
        }
        refreshStatusIcon()
    }

    // MARK: Timer

    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                ScrollInverter.shared.retryIfNeeded()
                self?.updateToggleItem()
            }
        }
    }

    // MARK: Actions

    @objc private func toggleReverseScroll() {
        let newValue = !ScrollInverter.shared.desiredEnabled
        ScrollInverter.shared.setEnabled(newValue)
        defaults.set(newValue, forKey: DefaultsKey.reverseMouseScrollEnabled)
        updateToggleItem()
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !defaults.bool(forKey: DefaultsKey.launchAtLoginEnabled)
        do {
            try LaunchAgentManager.shared.setEnabled(newValue)
            defaults.set(newValue, forKey: DefaultsKey.launchAtLoginEnabled)
            updateLaunchItem()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectIconStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = StatusIconStyle(rawValue: rawValue) else { return }
        defaults.set(style.rawValue, forKey: DefaultsKey.statusIconStyle)
        updateIconMenu()
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusMenuController = StatusMenuController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop the daemon when the app quits
        ScrollInverter.shared.setEnabled(false)
    }
}

// MARK: - Entry point

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
