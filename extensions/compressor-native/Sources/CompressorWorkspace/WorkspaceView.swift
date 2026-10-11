import AppKit
import SwiftUI
import VehlaNativeUISDK

struct CompressorWorkspaceView: View {
    @ObservedObject var model: CompressorModel
    @ObservedObject var themeBox: ThemeBox
    @State private var dropTargeted = false

    private var theme: VehlaWorkspaceTheme { themeBox.theme }
    private var secondary: Color { Color(nsColor: theme.secondaryTextColor) }

    var body: some View {
        ZStack {
            GlassBackdrop(base: Color(nsColor: theme.backgroundColor), isDark: theme.isDark, tinted: model.tinted)
            content
        }
        // Long paths and file names must never widen the window: report a
        // fixed ideal size and let the content truncate inside it.
        .frame(minWidth: 0, idealWidth: 560, maxWidth: .infinity,
               minHeight: 0, idealHeight: 420, maxHeight: .infinity)
        .environment(\.glassTinted, model.tinted)
        .foregroundStyle(Color(nsColor: theme.primaryTextColor))
        .preferredColorScheme(theme.isDark ? .dark : .light)
        // Installing a tool happens in Terminal, so re-check when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDependencies()
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls.filter(\.isFileURL))
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var content: some View {
        VStack(spacing: 16) {
            header
            dependencyBanner
            if model.items.isEmpty { dropZone } else { fileList }
            qualityCard
            destinationCard
            noticeBanner
            footer
        }
        .animation(.smooth, value: model.notice)
        .animation(.smooth, value: model.missingRequired)
        .padding(22)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.tinted ? Color.white : Color.primary)
                .frame(width: 50, height: 50)
                .glassCard(cornerRadius: 25, tint: Brand.indigo, strength: 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compressor").font(.title2.weight(.semibold))
                Text("Smaller files, same quality.").font(.callout).foregroundStyle(secondary)
            }
            Spacer()
            Button { withAnimation(.smooth) { model.toggleTint() } } label: {
                Image(systemName: model.tinted ? "paintpalette.fill" : "paintpalette")
            }
            .glassButton()
            .help(model.tinted ? "Switch to plain Liquid Glass" : "Switch to tinted Liquid Glass")
            if model.phase == .finished, model.totalSaved > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Saved").font(.caption).foregroundStyle(secondary)
                    Text(Format.bytes(model.totalSaved))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassCard(cornerRadius: 16, tint: Brand.sky, strength: 0.35)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: model.totalSaved)
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: dropTargeted ? "tray.and.arrow.down.fill" : "square.and.arrow.down")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Brand.blue)
                .scaleEffect(dropTargeted ? 1.12 : 1)
            Text(dropTargeted ? "Release to add" : "Drop files here")
                .font(.title3.weight(.semibold))
            Text("Images, videos, PDFs, documents and folders")
                .font(.callout).foregroundStyle(secondary)
            Button("Choose Files…") { model.chooseFiles() }
                .glassButton()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 28, tint: Brand.indigo, strength: dropTargeted ? 0.42 : 0.20)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Brand.sky.opacity(dropTargeted ? 0.9 : 0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .padding(10)
        )
        .animation(.smooth(duration: 0.2), value: dropTargeted)
    }

    // MARK: File list

    private var fileList: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.items) { item in row(item) }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
            if model.phase == .idle {
                Button { model.chooseFiles() } label: { Label("Add more", systemImage: "plus") }
                    .glassButton()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ item: FileItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline).lineLimit(1).truncationMode(.middle)
                detail(item)
            }
            Spacer(minLength: 8)
            trailing(item)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard(cornerRadius: 18, tint: Brand.blue, strength: 0.14)
    }

    @ViewBuilder private func detail(_ item: FileItem) -> some View {
        switch item.state {
        case .pending:
            Text("\(item.kind.label) · \(Format.bytes(item.size))").font(.caption).foregroundStyle(secondary)
        case .working(let value):
            ProgressView(value: value).tint(Brand.sky).frame(maxWidth: 220)
        case .done(let result):
            switch result.status {
            case .compressed:
                Text("\(Format.bytes(result.before)) → \(Format.bytes(result.after))")
                    .font(.caption.monospacedDigit()).foregroundStyle(secondary)
            case .failed:
                Text(result.message ?? "Failed").font(.caption).foregroundStyle(.red).lineLimit(3)
            default:
                Text(result.message ?? "").font(.caption).foregroundStyle(secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder private func trailing(_ item: FileItem) -> some View {
        switch item.state {
        case .pending:
            if model.phase != .running {
                Button { model.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(secondary)
            }
        case .working(let value):
            Text("\(Int(value * 100))%").font(.callout.monospacedDigit()).foregroundStyle(secondary)
        case .done(let result):
            switch result.status {
            case .compressed:
                Text("−\(Int((result.savedFraction * 100).rounded()))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassCard(cornerRadius: 12, tint: .green, strength: 0.40)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            default:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.sky)
            }
        }
    }

    // MARK: Missing tools

    @ViewBuilder private var dependencyBanner: some View {
        if !model.missingRequired.isEmpty {
            requiredToolsBanner
        } else if !model.missingOptional.isEmpty, !model.hideOptionalHint {
            optionalToolsHint
        }
    }

    private var requiredToolsBanner: some View {
        let missing = model.missingRequired
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some tools are missing").font(.callout.weight(.semibold))
                    Text("Needed for \(Dependencies.summary(missing)).")
                        .font(.caption).foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.homebrewAvailable {
                        Text("Homebrew isn't installed. Get it from brew.sh first, then run:")
                            .font(.caption).foregroundStyle(secondary)
                    }
                    Text(Dependencies.installCommand(missing))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { model.copyInstallCommand(missing) } label: { Label("Copy install command", systemImage: "doc.on.doc") }
                    .glassButton()
                if !model.homebrewAvailable {
                    Button { model.openHomebrewSite() } label: { Label("Get Homebrew", systemImage: "arrow.up.forward.square") }
                        .glassButton()
                }
                Button { model.refreshDependencies() } label: { Label("Check again", systemImage: "arrow.clockwise") }
                    .glassButton()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCard(cornerRadius: 18, tint: .orange, strength: 0.30)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var optionalToolsHint: some View {
        let missing = model.missingOptional
        return HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Brand.sky)
            Text("Tip: install \(missing.map(\.formula).joined(separator: ", ")) for \(missing.map(\.purpose).joined(separator: ", ")).")
                .font(.caption)
            Spacer(minLength: 8)
            Button("Copy command") { model.copyInstallCommand(missing) }.glassButton()
            Button { model.dismissOptionalHint() } label: { Image(systemName: "xmark") }
                .glassButton().help("Don't show this again")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassCard(cornerRadius: 16, tint: Brand.blue, strength: 0.20)
    }

    // MARK: Quality

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quality").font(.caption).foregroundStyle(secondary)
                Spacer()
                Text(model.quality.detail).font(.caption).foregroundStyle(secondary)
            }
            Picker("Quality", selection: Binding(get: { model.quality }, set: { model.setQuality($0) })) {
                ForEach(QualityPreset.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(model.phase == .running)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCard(cornerRadius: 20, tint: Brand.indigo, strength: 0.22)
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassCard(cornerRadius: 18, tint: .orange, strength: 0.30)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Destination + footer

    private var destinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3).foregroundStyle(Brand.sky)
            VStack(alignment: .leading, spacing: 2) {
                Text("Destination folder").font(.caption).foregroundStyle(secondary)
                Text(model.destination.map { Self.display($0) } ?? "Choose where to save")
                    .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Button("Choose…") { model.chooseDestination() }
                .glassButton().disabled(model.phase == .running)
            if model.destination != nil {
                Button { model.openDestination() } label: { Image(systemName: "arrow.up.forward.app") }
                    .glassButton().help("Open in Finder")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCard(cornerRadius: 20, tint: Brand.indigo, strength: 0.22)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle("Open folder when done", isOn: $model.openWhenDone)
                .toggleStyle(.switch).tint(Brand.blue)
                .disabled(model.phase == .running)
            Spacer()
            switch model.phase {
            case .running:
                Button("Cancel") { model.cancel() }.glassButton()
            case .finished:
                Button("New Batch") { model.newBatch() }.glassButton()
                if model.canStart { startButton }
            case .idle:
                startButton
            }
        }
    }

    private var startButton: some View {
        let count = model.items.filter { if case .pending = $0.state { true } else { false } }.count
        return Button { model.start() } label: {
            Label(count > 0 ? "Compress \(count) item\(count == 1 ? "" : "s")" : "Compress",
                  systemImage: "wand.and.sparkles")
        }
        .glassButton(prominent: true)
        .controlSize(.large)
        .disabled(!model.canStart)
    }

    private static func display(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
