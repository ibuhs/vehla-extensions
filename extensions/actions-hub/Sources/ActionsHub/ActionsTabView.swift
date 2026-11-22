import ActionsHubCore
import AppKit
import NotchKit
import SwiftUI

/// One thing you can tap, whatever its kind.
private struct HubItem: Identifiable {
    enum Kind: String, CaseIterable { case scenes = "Scenes", toggles = "Toggles", shortcuts = "Shortcuts", apps = "Apps" }

    let id: String
    let kind: Kind
    let title: String
    let systemImage: String
    var icon: NSImage?
    var active = false
    var busy = false
    var disabled = false
    let help: String
    let action: () -> Void
}

struct ActionsTabView: View {
    @ObservedObject var model: ActionsModel
    @State private var filter: HubItem.Kind?

    // Compact on purpose: the Notch gives a tab about 160pt, so single-row tiles fit three rows at once.
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 5)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if shown.isEmpty {
                NKEmptyState("square.grid.2x2", title: "Nothing here yet",
                             message: "Add scenes and apps in actions.json, or create Shortcuts.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(shown) { CompactTile(item: $0) }
                    }
                }
            }
        }
        .nkTab()
        .onAppear { model.tabVisible(true) }
        .onDisappear { model.tabVisible(false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Actions").font(.system(size: 15, weight: .semibold)).padding(.trailing, 4)
            filterChip("All", selected: filter == nil) { filter = nil }
            ForEach(kinds, id: \.self) { kind in
                filterChip(kind.rawValue, selected: filter == kind) { filter = (filter == kind ? nil : kind) }
            }
            Spacer(minLength: 0)
            NKStatusLine(model.status).frame(maxWidth: 180, alignment: .trailing)
            NKIconButton("arrow.clockwise", help: "Reload Shortcuts and state", size: 22) {
                Task { await model.refreshShortcuts(); await model.refreshToggles() }
            }
            NKIconButton("slider.horizontal.3", help: "Edit scenes and apps (actions.json)", size: 22) { model.revealConfig() }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(selected ? NK.Palette.surfaceRaised : .clear))
                .foregroundStyle(selected ? NK.Palette.primary : NK.Palette.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Items

    private var kinds: [HubItem.Kind] { HubItem.Kind.allCases.filter { kind in items.contains { $0.kind == kind } } }
    private var shown: [HubItem] { filter == nil ? items : items.filter { $0.kind == filter } }

    private var items: [HubItem] {
        var all: [HubItem] = []
        for scene in model.config.scenes {
            let running = model.scene?.id == scene.id
            all.append(HubItem(id: "scene-\(scene.id)", kind: .scenes, title: scene.name, systemImage: scene.icon,
                               busy: running, disabled: model.scene != nil && !running,
                               help: scene.steps.map(\.summary).joined(separator: "\n"), action: { model.run(scene) }))
        }
        for toggle in model.config.toggles {
            all.append(HubItem(id: "toggle-\(toggle.rawValue)", kind: .toggles, title: toggle.title,
                               systemImage: toggle.systemImage, active: model.toggleStates[toggle] ?? false,
                               busy: model.busyToggles.contains(toggle), help: "Toggle \(toggle.title)",
                               action: { model.flip(toggle) }))
        }
        for name in model.shortcuts {
            all.append(HubItem(id: "shortcut-\(name)", kind: .shortcuts, title: name, systemImage: "wand.and.stars",
                               busy: model.runningShortcut == name,
                               disabled: model.runningShortcut != nil && model.runningShortcut != name,
                               help: "Run \(name)", action: { model.runShortcut(name) }))
        }
        for app in model.config.apps {
            all.append(HubItem(id: "app-\(app.name)", kind: .apps, title: app.name, systemImage: "app.dashed",
                               icon: AppIcons.icon(for: app.name), help: "Open \(app.name)",
                               action: { model.open(app: app) }))
        }
        return all
    }
}

// MARK: - Tile

private struct CompactTile: View {
    let item: HubItem
    @State private var hovering = false

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 6) {
                ZStack {
                    if item.busy {
                        ProgressView().controlSize(.mini)
                    } else if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: item.systemImage).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.active ? .white : tint)
                    }
                }
                .frame(width: 16, height: 16)
                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(item.active ? .white : NK.Palette.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.active ? Color.accentColor.opacity(0.9)
                                      : (hovering ? NK.Palette.surfaceRaised : NK.Palette.surface))
            )
            .opacity(item.disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(item.disabled)
        .onHover { hovering = $0 }
        .help(item.help)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.active ? .isSelected : [])
    }

    /// A quiet colour per kind so the mixed grid stays scannable without section headings.
    private var tint: Color {
        switch item.kind {
        case .scenes: return NK.Palette.mindful
        case .toggles: return NK.Palette.info
        case .shortcuts: return NK.Palette.warning
        case .apps: return NK.Palette.secondary
        }
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        for folder in folders {
            let path = "\(folder)/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                let image = NSWorkspace.shared.icon(forFile: path)
                cache[name] = image
                return image
            }
        }
        return nil
    }
}
