import AgentApprovalsCore
import NotchKit
import SwiftUI

struct AgentsTabView: View {
    @ObservedObject var model: ApprovalsModel
    @State private var showingSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Group {
                if showingSetup {
                    SetupView(model: model)
                } else if model.sessions.isEmpty && model.recentSessions.isEmpty && model.pending.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .nkTab()
        .animation(.easeOut(duration: 0.15), value: model.pending.count)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(showingSetup ? "Setup" : "Agents").font(.system(size: 15, weight: .semibold))
            if !showingSetup, activeCount > 0 {
                HStack(spacing: 5) {
                    Circle().fill(NK.Palette.success).frame(width: 7, height: 7)
                    Text("\(activeCount) active").font(NK.Font.label).foregroundStyle(NK.Palette.success)
                }
            }
            if !showingSetup, !model.pending.isEmpty {
                NKChip("\(model.pending.count) need\(model.pending.count == 1 ? "s" : "") you", tone: .orange)
            }
            Spacer(minLength: 0)
            NKStatusLine(model.status).frame(maxWidth: 240, alignment: .trailing)
            NKIconButton(showingSetup ? "xmark" : "gearshape", help: showingSetup ? "Close setup" : "Hook setup") {
                showingSetup.toggle()
            }
        }
    }

    private var activeCount: Int { model.sessions.count }

    // MARK: Content

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let head = model.pending.first {
                    ApprovalCard(item: head, more: model.pending.count - 1, model: model)
                        .padding(.bottom, 4)
                }
                ForEach(model.sessions) { SessionRow(session: $0) }
                if !model.recentSessions.isEmpty {
                    NKSectionHeader("Recent").padding(.top, 8).padding(.bottom, 2)
                    ForEach(model.recentSessions) { SessionRow(session: $0, ended: true) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            NKEmptyState("terminal", title: "No agents running",
                         message: model.scriptInstalled ? "Start Claude Code and it will appear here."
                                                        : "Install the hooks to monitor agents and approve requests.")
            if !model.scriptInstalled {
                Button("Set up hooks") { showingSetup = true }.buttonStyle(NKPillButtonStyle(.primary))
            }
        }
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: AgentSession
    var ended = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SessionAvatar(state: ended ? nil : session.state)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.project).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !ended { NKChip(statusText, tone: statusTone) }
                    if let model = session.model { NKChip(Format.model(model), tone: modelTone(model)) }
                    if let branch = session.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .semibold))
                            Text(branch).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        }
                        .foregroundStyle(NK.Palette.secondary)
                    }
                }
                if let task = session.task {
                    Text(task).font(NK.Font.body).foregroundStyle(NK.Palette.primary.opacity(0.85)).lineLimit(1)
                }
                if !ended, let activity = session.activity {
                    Text(activity).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NK.Palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                elapsed.font(NK.Font.body.monospacedDigit()).foregroundStyle(NK.Palette.secondary)
                Text(counts).font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
            }
        }
        .padding(.vertical, 8)
        .opacity(ended ? 0.6 : 1)
        .overlay(alignment: .bottom) { Rectangle().fill(NK.Palette.stroke).frame(height: 1) }
    }

    @ViewBuilder private var elapsed: some View {
        if let endedAt = session.endedAt {
            Text(Format.elapsed(endedAt.timeIntervalSince(session.startedAt)))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Format.elapsed(context.date.timeIntervalSince(session.startedAt)))
            }
        }
    }

    private var counts: String {
        var parts: [String] = []
        if session.messages > 0 { parts.append("\(session.messages) msgs") }
        if session.tokens > 0 { parts.append("\(Format.tokens(session.tokens)) tok") }
        return parts.joined(separator: " · ")
    }

    private var statusText: String {
        switch session.state {
        case .working: return "Running"
        case .waiting: return "Approval"
        case .idle: return "Waiting"
        }
    }

    private var statusTone: NKChip.Tone {
        switch session.state {
        case .working: return .green
        case .waiting: return .orange
        case .idle: return .blue
        }
    }

    private func modelTone(_ model: String) -> NKChip.Tone {
        switch Format.family(model) {
        case .opus: return .orange
        case .sonnet: return .blue
        case .haiku: return .green
        case .fable: return .purple
        case .other: return .neutral
        }
    }
}

/// A terminal glyph in a rounded tile with a small status dot, like an app icon.
private struct SessionAvatar: View {
    let state: AgentState?

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(NK.Palette.surfaceRaised)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NK.Palette.secondary)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(dot).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
    }

    private var dot: Color {
        switch state {
        case .working: return NK.Palette.success
        case .waiting: return NK.Palette.warning
        case .idle: return NK.Palette.info
        case nil: return NK.Palette.tertiary
        }
    }
}

// MARK: - Approval

private struct ApprovalCard: View {
    let item: PendingApproval
    let more: Int
    @ObservedObject var model: ApprovalsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(riskColor).frame(width: 7, height: 7)
                Text(item.summary.risk.label).font(NK.Font.label).foregroundStyle(riskColor)
                Text("·").foregroundStyle(NK.Palette.tertiary)
                Text(item.event.project).font(NK.Font.label).foregroundStyle(NK.Palette.secondary)
                Spacer(minLength: 0)
                if more > 0 { Text("+\(more) more").font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary) }
            }
            HStack(alignment: .top, spacing: 8) {
                Text(item.summary.title).font(NK.Font.title)
                Text(item.summary.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NK.Palette.primary.opacity(0.9))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Deny") { model.decide(item, allow: false) }.buttonStyle(NKPillButtonStyle(.secondary))
                if AllowRules.isRememberable(item.event) {
                    Button("Always allow") { model.decide(item, allow: true, always: true) }
                        .buttonStyle(NKPillButtonStyle(.secondary))
                        .help("Allow this kind of request for the rest of this session")
                }
                Button("Allow") { model.decide(item, allow: true) }
                    .buttonStyle(NKPillButtonStyle(item.summary.risk == .high ? .destructive : .primary))
            }
        }
        .nkCard(padding: 10, highlighted: true)
    }

    private var riskColor: Color {
        switch item.summary.risk {
        case .low: return NK.Palette.success
        case .medium: return NK.Palette.warning
        case .high: return NK.Palette.danger
        }
    }
}

// MARK: - Setup

private struct SetupView: View {
    @ObservedObject var model: ApprovalsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1, "Install the hook script", done: model.scriptInstalled) {
                Button(model.scriptInstalled ? "Reinstall" : "Install") { model.installScript() }
                    .buttonStyle(NKPillButtonStyle(model.scriptInstalled ? .secondary : .primary))
            }
            step(2, "Add the hooks to ~/.claude/settings.json", done: false) {
                Button("Copy settings") { model.copySnippet() }.buttonStyle(NKPillButtonStyle(.primary))
            }
            HStack(spacing: 6) {
                Circle().fill(model.serverError == nil ? NK.Palette.success : NK.Palette.danger).frame(width: 7, height: 7)
                Text(model.serverError ?? "Listening for agents").font(NK.Font.caption)
                    .foregroundStyle(NK.Palette.secondary)
            }
            Text("If the Notch is off or you don't answer, Claude Code asks as usual.")
                .font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
        }
    }

    private func step<Action: View>(_ n: Int, _ title: String, done: Bool,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? NK.Palette.success : NK.Palette.surfaceRaised).frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                } else {
                    Text("\(n)").font(NK.Font.caption)
                }
            }
            Text(title).font(NK.Font.body).lineLimit(1)
            Spacer(minLength: 0)
            action()
        }
    }
}
