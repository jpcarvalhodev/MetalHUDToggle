import SwiftUI
import AppKit
import Combine

/// Borderless panel that can receive clicks/keys without activating the app.
final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Distance (in points) between the bottom of the menu bar and the top of the panel.
    /// Increase it to move the panel further from the icon, decrease it to bring it closer.
    private let gapBelowMenuBar: CGFloat = 6

    private let model = HUDModel()
    private var statusItem: NSStatusItem?
    private var panel: PopoverPanel?
    private var hostingView: NSHostingView<MenuView>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.image(active: model.enabled)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        // Keep the menu bar glyph in sync with the master switch.
        model.$enabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.statusItem?.button?.image = MenuBarIcon.image(active: active)
            }
            .store(in: &cancellables)
    }

    // MARK: Status item clicks

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            showContextMenu()
        } else {
            togglePanel(sender)
        }
    }

    private func showContextMenu() {
        hidePanel()

        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Metal HUD Toggle",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        // Attach the menu only for this click so left-clicks keep opening the panel.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Show / hide

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        var size = hostingView?.fittingSize ?? .zero
        if size.width < 100 || size.height < 100 {
            size = NSSize(width: 340, height: 560)
        }

        let anchor = buttonWindow.frame
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor

        // Center under the icon, but keep the panel fully on screen.
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)

        // visibleFrame.maxY is the bottom edge of the menu bar (also correct on notched Macs).
        let top = min(anchor.minY, visible.maxY) - gapBelowMenuBar

        panel.setFrame(
            NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
            display: false
        )
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        button.highlight(true)
        startMonitors()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        stopMonitors()
    }

    /// Keeps the top edge fixed while the content grows or shrinks (e.g. expanding a group).
    private func resizePanel(to size: CGSize) {
        guard let panel, panel.isVisible, size.width > 0, size.height > 0 else { return }
        let frame = panel.frame
        if abs(frame.width - size.width) < 0.5 && abs(frame.height - size.height) < 0.5 { return }

        panel.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
        panel.invalidateShadow()
    }

    // MARK: Panel construction

    private func makePanel() -> PopoverPanel {
        let root = MenuView(model: model) { [weak self] size in
            self?.resizePanel(to: size)
        }
        let hosting = NSHostingView(rootView: root)
        hostingView = hosting

        // Translucent, rounded background.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Theme.cornerRadius)

        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let panel = PopoverPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    /// Stretchable rounded-rect mask (the supported way to round an NSVisualEffectView).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Dismissal (click outside / Esc)

    private func startMonitors() {
        stopMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hidePanel()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.hidePanel()
                return nil
            }
            return event
        }
    }

    private func stopMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
