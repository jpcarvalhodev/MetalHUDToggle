import SwiftUI
import AppKit

// MARK: - Menu bar glyph

enum MenuBarIcon {
    /// A tiny "HUD" glyph: a rounded rectangle with a frame-time graph inside.
    /// When active, the rectangle is filled and the graph is cut out of it.
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            let body = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: 3.5,
                yRadius: 3.5
            )

            let graph = NSBezierPath()
            graph.move(to: NSPoint(x: 4.5, y: 5.0))
            graph.line(to: NSPoint(x: 7.5, y: 8.5))
            graph.line(to: NSPoint(x: 10.0, y: 6.0))
            graph.line(to: NSPoint(x: 12.5, y: 10.0))
            graph.line(to: NSPoint(x: 15.5, y: 7.0))
            graph.lineWidth = 1.5
            graph.lineCapStyle = .round
            graph.lineJoinStyle = .round

            NSColor.black.setFill()
            NSColor.black.setStroke()

            if active {
                body.fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                graph.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                body.lineWidth = 1.3
                body.stroke()
                graph.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.20, green: 0.91, blue: 0.55)
    static let cornerRadius: CGFloat = 20
}

// MARK: - Popover content

struct MenuView: View {
    @ObservedObject var model: HUDModel
    /// Reports the total content size so the hosting panel can resize itself.
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var expandedGroups: Set<HUDGroup> = []
    // ScrollView has no intrinsic height inside a hosting panel, so we measure
    // the content and size the scroll area ourselves (capped so it never outgrows the screen).
    @State private var contentHeight: CGFloat = 500
    private let maxScrollHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metricsSection
                    appearanceSection
                    loggingSection
                    startupSection
                }
                .padding(14)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(height: min(contentHeight, maxScrollHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

            Divider()

            footer
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PanelSizeKey.self) { onSizeChange($0) }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Metal HUD")
                    .font(.system(size: 15, weight: .semibold))
                Text(model.enabled ? "On · restart running apps to apply" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("Metal HUD", isOn: $model.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Metrics

    private var metricsSection: some View {
        SettingsSection("Metrics") {
            ForEach(Array(HUDGroup.allCases.enumerated()), id: \.element) { index, group in
                if index > 0 { RowDivider() }

                GroupHeader(
                    group: group,
                    activeCount: model.activeCount(in: group),
                    totalCount: HUDElement.allCases.filter { $0.group == group }.count,
                    isExpanded: expandedGroups.contains(group)
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedGroups.contains(group) {
                            expandedGroups.remove(group)
                        } else {
                            expandedGroups.insert(group)
                        }
                    }
                }

                if expandedGroups.contains(group) {
                    ForEach(HUDElement.allCases.filter { $0.group == group }) { element in
                        RowDivider()
                        SwitchRow(title: element.title, isOn: model.binding(for: element))
                    }
                }
            }

            if model.elements.isEmpty {
                RowDivider()
                Text("Nothing selected — the system default set is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            SwitchRow(title: "Custom position", isOn: $model.overrideAlignment)
            if model.overrideAlignment {
                HStack {
                    Spacer()
                    PositionGrid(selection: $model.alignment)
                    Spacer()
                }
                .padding(.bottom, 10)
            }

            RowDivider()

            SwitchRow(title: "Custom scale", isOn: $model.overrideScale)
            if model.overrideScale {
                SliderRow(value: $model.scale, range: 0.1...1.0)
            }

            RowDivider()

            SwitchRow(title: "Custom opacity", isOn: $model.overrideOpacity)
            if model.overrideOpacity {
                SliderRow(value: $model.opacity, range: 0.1...1.0)
            }
        }
    }

    // MARK: Logging

    private var loggingSection: some View {
        SettingsSection("Logging") {
            SwitchRow(
                title: "Log frame stats",
                subtitle: "View in Console, filter by “metal-HUD”",
                isOn: $model.logFrames
            )
            RowDivider()
            SwitchRow(title: "Log shader compilation", isOn: $model.logShaders)
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSection("Startup") {
                SwitchRow(title: "Start at login", isOn: $model.launchAtLogin)
                RowDivider()
                SwitchRow(
                    title: "Start at login with HUD on",
                    isOn: $model.enableHUDAtLogin
                )
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}

struct SwitchRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct GroupHeader: View {
    let group: HUDGroup
    let activeCount: Int
    let totalCount: Int
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.symbol)
                .frame(width: 18)
                .foregroundStyle(Theme.accent)
            Text(group.rawValue)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Text("\(activeCount)/\(totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct SliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// 3x3 grid that mirrors the screen; tap a cell to place the HUD there.
struct PositionGrid: View {
    @Binding var selection: HUDAlignment

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(HUDAlignment.allCases) { position in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selection == position ? Theme.accent : Color.primary.opacity(0.14))
                    .frame(width: 34, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = position }
                    .help(position.title)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
    }
}
