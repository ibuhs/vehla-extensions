import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(PureSnitchWorkspacePlugin)
public final class PureSnitchWorkspacePlugin: NSObject, VehlaNativeWorkspacePlugin {
    public override required init() { super.init() }
    public var apiVersion: Int { VehlaNativeUIAPIVersion }
    public var workspaces: [VehlaWorkspaceDescriptor] {
        [VehlaWorkspaceDescriptor(
            id: "puresnitch", title: "PureSnitch", subtitle: "Network monitor and firewall",
            systemImage: "shield.lefthalf.filled", preferredWidth: 1180, preferredHeight: 760,
            minimumWidth: 940, minimumHeight: 600, dismissBehavior: .persistent
        )]
    }

    @MainActor
    public func makeViewController(workspaceID: String, context: VehlaWorkspaceContext) throws -> NSViewController {
        guard workspaceID == "puresnitch" else {
            throw NSError(domain: "PureSnitchWorkspace", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown PureSnitch workspace."])
        }
        let state = AppState()
        let initialTab: PureSnitchTab
        switch context.launchRequest.commandID {
        case "rules": initialTab = .rules
        case "settings": initialTab = .settings
        default: initialTab = .monitor
        }
        return PureSnitchWorkspaceController(state: state, initialTab: initialTab)
    }
}

/// SwiftUI can create the replacement before dismantling the previous host.
/// A plugin-wide workspaceWillClose callback has only a workspace ID and
/// cannot identify which controller is closing. Tie the subscription to its
/// actual controller instead, leaving the persistent firewall untouched.
@MainActor
final class PureSnitchWorkspaceController: NSHostingController<PureSnitchWorkspaceView> {
    private let workspaceState: AppState

    init(state: AppState, initialTab: PureSnitchTab) {
        workspaceState = state
        super.init(rootView: PureSnitchWorkspaceView(state: state, initialTab: initialTab))
        sizingOptions = []
        view.appearance = NSAppearance(named: .darkAqua)
        state.helper.connect()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(state:initialTab:)") }

    override func viewWillAppear() {
        super.viewWillAppear()
        workspaceState.helper.connect()
    }

    override func viewWillDisappear() {
        workspaceState.helper.disconnect()
        super.viewWillDisappear()
    }

    deinit {
        let state = workspaceState
        Task { @MainActor in state.helper.disconnect() }
    }
}

enum PureSnitchTab: String, CaseIterable {
    case monitor = "Monitor", rules = "Rules", settings = "Settings", activity = "Activity"
    var symbol: String {
        switch self {
        case .monitor: return "network"
        case .rules: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        case .activity: return "waveform.path"
        }
    }
}

struct PureSnitchWorkspaceView: View {
    @ObservedObject var state: AppState
    @State private var tab: PureSnitchTab

    init(state: AppState, initialTab: PureSnitchTab) {
        self.state = state
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("PureSnitch", systemImage: "shield.lefthalf.filled").font(.headline)
                ForEach(PureSnitchTab.allCases, id: \.self) { item in
                    Button { tab = item } label: { Label(item.rawValue, systemImage: item.symbol) }
                        .buttonStyle(.bordered)
                        .tint(tab == item ? PSTheme.accent : .secondary)
                }
                Spacer()
                Circle().fill(state.helperConnected ? PSTheme.accentGreen : PSTheme.accentYellow)
                    .frame(width: 7, height: 7)
                Text(state.helperConnected ? "Connected" : "Helper offline")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            Group {
                switch tab {
                case .monitor: NetworkMonitorView()
                case .rules: RulesManagerView()
                case .settings: SettingsView()
                case .activity: activityView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("↑ \(ByteCountFormatter.string(fromByteCount: state.currentOut, countStyle: .binary))/s")
                Text("↓ \(ByteCountFormatter.string(fromByteCount: state.currentIn, countStyle: .binary))/s")
                Spacer()
                Text("Host-wide IPv4 rules · experimental DNS proxy · no per-app filtering")
            }
            .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .environmentObject(state)
        .background(PSTheme.bgPrimary)
        .foregroundStyle(PSTheme.textPrimary)
        .preferredColorScheme(.dark)
        .overlay { AlertOverlayContainer().environmentObject(state) }
    }

    private var activityView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HelperBanner()
            Text("Recent Activity").font(.title2.bold())
            if state.logs.isEmpty {
                Text("Helper events will appear here while this workspace is open.").foregroundStyle(.secondary)
            }
            List(state.logs.reversed()) { entry in
                HStack(alignment: .top) {
                    Text(entry.timestamp, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(entry.level.uppercased()).font(.caption.bold()).frame(width: 65, alignment: .leading)
                    Text(entry.message).font(.caption).textSelection(.enabled)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(16)
    }
}
