import AppKit

// Pure AppKit entry point: no SwiftUI scenes, so macOS never opens a window at launch.
// The whole UI is the menu bar item + panel created in AppDelegate.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, no app menu
app.run()
