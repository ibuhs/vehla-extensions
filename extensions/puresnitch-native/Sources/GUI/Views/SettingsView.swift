import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var doh = ""
    @State private var lastUpstream = ""
    @State private var showingRemoveHelperConfirmation = false
    @State private var tab: SettingsTab = .general

    private enum SettingsTab: String, CaseIterable {
        case general = "General", dns = "DNS", blocklists = "Blocklists", profiles = "Profiles", about = "About"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                            .foregroundColor(tab == item ? PSTheme.textPrimary : PSTheme.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(tab == item ? PSTheme.bgTertiary : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
            Group {
                switch tab {
                case .general: generalTab
                case .dns: dnsTab
                case .blocklists: blocklistsTab
                case .profiles: profilesTab
                case .about: aboutTab
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: 760, maxHeight: .infinity)
        .confirmationDialog(
            "Remove the privileged helper?",
            isPresented: $showingRemoveHelperConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Helper", role: .destructive) {
                state.helper.unregisterDaemon()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PureSnitch will stop monitoring until the helper is installed and approved again. Enforcement must already be off so removal cannot leave or silently clear firewall state.")
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HelperBanner()
            Form {
                Section("Privileged helper") {
                    HStack {
                        Text(helperSummary)
                        Spacer()
                        Button("Check Again") { state.helper.refreshInstallState(); state.helper.ping() }
                    }
                    if state.helperInstallState != .enabled {
                        Button("Open Login Items…") { state.helper.openLoginItemsSettings() }
                    }
                    if state.helperInstallState == .enabled {
                        Button("Remove Helper…", role: .destructive) {
                            showingRemoveHelperConfirmation = true
                        }
                        .disabled(removeHelperDisabled)
                        Text("Turn Enforcement Off and wait for both runtime components to stop before removing the helper.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Service installation") {
                    Text("Install Helper adds Vehla PureSnitch Service to your Applications folder. Approve it in Login Items to start monitoring. The helper stays installed when this workspace closes or the extension is removed; turn Enforcement Off and use Remove Helper before uninstalling.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Enforcement") {
                    Toggle(
                        "Block traffic, don't just watch it",
                        isOn: Binding(
                            get: { state.enforcementEnabled },
                            set: { state.requestEnforcementDesired($0) }
                        )
                    )
                        .disabled(!state.helperConnected || !state.helperStatusLoaded || state.enforcementRequestInFlight || state.modeRequestInFlight)
                    HStack {
                        Text("Runtime status")
                        Spacer()
                        Text(enforcementRuntimeSummary).foregroundColor(.secondary)
                    }
                    Text("Experimental and off by default. This loads a pf firewall anchor and starts a local DNS proxy on port \(AppConstants.dnsProxyPort). PureSnitch does not change macOS DNS settings; DNS filtering applies only if you manually configure this Mac or an app to use the proxy. Leave this off for monitoring only.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Mode") {
                    Picker("Default mode", selection: Binding(get: { state.mode }, set: { state.setMode($0) })) {
                        Text("Alert").tag(AppMode.alert)
                        Text("Silent Allow").tag(AppMode.silentAllow)
                        Text("Silent Deny").tag(AppMode.silentDeny)
                    }
                    .disabled(!state.helperConnected || !state.helperStatusLoaded || state.enforcementRequestInFlight || state.modeRequestInFlight)
                }
            }
            .formStyle(.grouped)
            Spacer(minLength: 0)
        }
    }

    private var helperSummary: String {
        switch state.helperInstallState {
        case .enabled: return state.helperConnected ? "Connected" : "Approved, connecting…"
        case .requiresApproval: return "Waiting for your approval"
        case .notRegistered, .unknown: return "Not installed"
        case .wrongLocation: return "Install the service in your Applications folder"
        case .notFound: return "Missing from this build"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    private var removeHelperDisabled: Bool {
        !state.helperConnected
            || !state.helperStatusLoaded
            || state.enforcementEnabled
            || state.pfctlEnabled
            || state.dnsProxyEnabled
            || state.enforcementRequestInFlight
            || state.modeRequestInFlight
    }

    private var enforcementRuntimeSummary: String {
        if !state.helperConnected { return "Helper disconnected; runtime unknown" }
        if !state.helperStatusLoaded { return "Loading helper status…" }
        if state.enforcementRequestInFlight { return "Applying requested state…" }
        switch (state.pfctlEnabled, state.dnsProxyEnabled) {
        case (true, true): return "Firewall and DNS proxy active"
        case (true, false): return "Firewall active; DNS proxy inactive"
        case (false, true): return "DNS proxy active; firewall inactive"
        case (false, false): return state.enforcementEnabled ? "Requested; waiting for helper" : "Inactive"
        }
    }

    private var dnsTab: some View {
        Form {
            Section("DNS over HTTPS upstream") {
                TextField("DoH URL", text: $doh)
                    .onSubmit { state.helper.setDoHUpstream(doh) }
                    .onAppear { doh = state.dohUpstream; lastUpstream = state.dohUpstream }
                    .onChange(of: state.dohUpstream) { _, value in
                        if doh == lastUpstream { doh = value }
                        lastUpstream = value
                    }
                Button("Save Upstream") { state.helper.setDoHUpstream(doh) }
                    .disabled(!state.helperConnected)
                if let error = state.dnsSettingsError { Text(error).font(.caption).foregroundColor(.red) }
                Text("Examples:").font(.caption).foregroundColor(.secondary)
                Text("https://cloudflare-dns.com/dns-query").font(.caption.monospaced())
                Text("https://dns.quad9.net/dns-query").font(.caption.monospaced())
                Text("https://dns.google/dns-query").font(.caption.monospaced())
            }
            Section("Local DNS proxy") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(dnsRuntimeSummary)
                        .foregroundColor(.secondary)
                }
                Text("The proxy runs inside the privileged helper and filters queries sent directly to it. PureSnitch does not configure it as the macOS system resolver; manual DNS configuration is required. Status changes only after the helper confirms it.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var dnsRuntimeSummary: String {
        guard state.helperConnected, state.helperStatusLoaded else { return "Runtime unknown" }
        return state.dnsProxyEnabled ? "Running on port \(AppConstants.dnsProxyPort)" : "Not running"
    }

    private var blocklistsTab: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Blocklists").font(.headline)
                Spacer()
                Button("Refresh All") { state.helper.refreshBlocklists() }
            }
            if state.blocklists.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No blocklists loaded")
                        .font(.body).foregroundColor(.secondary)
                    Text(state.helperConnected
                         ? "Press Refresh All to download the default blocklists."
                         : "Blocklists live in the privileged helper. Approve the helper first — see the General tab.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
            }
            List(state.blocklists) { b in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { b.enabled },
                        set: { newValue in
                            state.helper.enableBlocklist(id: b.id, enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading) {
                        Text(b.name).font(.body)
                        Text(b.url).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(b.entryCount)").font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var profilesTab: some View {
        VStack(alignment: .leading) {
            Text("Profiles (organizational only)").font(.headline)
            Text("PureSnitch 0.2.1 enforces only the default profile. Additional profiles can organize stored rules but cannot be activated.")
                .font(.caption).foregroundColor(.secondary)
            if state.profiles.isEmpty {
                Text("No profiles yet. Profiles come from the privileged helper's rule database.")
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach(state.profiles) { p in
                HStack {
                    Image(systemName: p.icon)
                    Text(p.name)
                    Spacer()
                    if p.name == "default" {
                        PSChip("Enforced", color: PSTheme.accentGreen)
                    } else {
                        PSChip("Stored only", color: PSTheme.textSecondary)
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 64)).foregroundColor(PSTheme.accent)
            Text("PureSnitch for Vehla").font(.title.bold())
            Text("v\(AppConstants.version)").font(.subheadline).foregroundColor(.secondary)
            Text("Based on PureSnitch \(AppConstants.upstreamVersion). Host-wide IPv4 firewall; no per-app filtering.").font(.caption).foregroundColor(.secondary)
            Link("github.com/momenbasel/puresnitch", destination: URL(string: "https://github.com/momenbasel/puresnitch")!)
                .font(.caption)
            Text("MIT License · © 2026 Moamen Basel")
                .font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
