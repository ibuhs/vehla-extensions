import SwiftUI
import VehlaDockWidgetSDK

struct LofiRootView: View {
    let surface: VehlaDockWidgetSurface
    let player: LofiPlayer
    var body: some View {
        Group {
            switch surface {
            case .compact: LofiTile(player: player)
            case .inline: LofiInline(player: player)
            case .popup: LofiPopup(player: player)
            @unknown default: EmptyView()
            }
        }
        .foregroundStyle(Color(nsColor: surface == .popup ? player.theme?.primaryTextColor ?? .labelColor : player.theme?.tileTextColor ?? .labelColor))
        .environment(\.colorScheme, player.theme?.isDark == true ? .dark : .light)
    }
}

private enum Cozy {
    // Dusk: plum into rose into warm amber.
    static let plum = Color(red: 0.20, green: 0.15, blue: 0.30)
    static let rose = Color(red: 0.55, green: 0.29, blue: 0.40)
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.40)
    static let cream = Color(red: 1.0, green: 0.93, blue: 0.82)
    static let gradient = LinearGradient(colors: [plum, rose, Color(red: 0.80, green: 0.50, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Three little bars that dance while music plays and rest when it doesn't.
private struct Equalizer: View {
    let active: Bool
    var tint: Color = Cozy.amber

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = active ? (sin(t * (3.2 + Double(i) * 1.1) + Double(i) * 1.7) + 1) / 2 : 0.25
                    RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3, height: 4 + 10 * phase)
                }
            }
            .frame(height: 15, alignment: .bottom)
        }
    }
}

private struct LofiTile: View {
    let player: LofiPlayer

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "music.note").font(.system(size: 19, weight: .medium))

            if player.isPlaying {
                Equalizer(active: true)
            } else {
                Text("lofi").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}

private struct LofiInline: View {
    let player: LofiPlayer

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "music.note").font(.system(size: 20, weight: .medium))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.isPlaying ? player.current.title : "Lofi").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(player.isPlaying ? "now playing" : "tap to relax").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if player.isPlaying { Equalizer(active: true) }
        }
        .padding(.horizontal, 12)
    }
}

/// A record that spins while the music plays.
private struct Vinyl: View {
    let spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !spinning)) { timeline in
            let degrees = (timeline.date.timeIntervalSinceReferenceDate * 40).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle().fill(Color.black.opacity(0.85))
                ForEach([0.86, 0.72, 0.58], id: \.self) { scale in
                    Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1).scaleEffect(scale)
                }
                // A highlight that sweeps round, so the spin is visible.
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                    .scaleEffect(0.7)
                    .rotationEffect(.degrees(degrees))
                Circle().fill(Cozy.gradient).scaleEffect(0.34)
                Circle().fill(Cozy.cream).scaleEffect(0.06)
            }
            .rotationEffect(.degrees(spinning ? degrees : 0))
        }
        .compositingGroup()
    }
}

private struct LofiPopup: View {
    let player: LofiPlayer
    @State private var showSourcePrompt = false
    private var secondary: Color { Color(nsColor: player.theme?.secondaryTextColor ?? .secondaryLabelColor) }

    var body: some View {
        VStack(spacing: 18) {
            header
            nowPlaying
            controls.disabled(player.tracks.isEmpty || player.isLoading)
            playlist
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // A bloom that fades before the edges: the host's glass stays seamless.
            GeometryReader { geometry in
                RadialGradient(colors: [Cozy.amber.opacity(0.13), Cozy.rose.opacity(0.07), .clear],
                    center: UnitPoint(x: 0.5, y: 0.24), startRadius: 0,
                    endRadius: min(geometry.size.width * 0.45, 180))
            }.allowsHitTesting(false)
        }
        .tint(Cozy.amber)
        .onAppear { if player.shouldPromptSource { showSourcePrompt = true } }
        .onChange(of: showSourcePrompt) { _, shown in if !shown { player.skipSourcePrompt() } }
        .sheet(isPresented: $showSourcePrompt) {
            VStack(spacing: 18) {
                Image(systemName: "folder.badge.plus").font(.system(size: 32)).foregroundStyle(Cozy.amber)
                Text("Where is your music?").font(.title3.bold())
                Text("Choose a folder of audio files to use as your Lofi library. Music stays in your folder; Lofi does not download or include songs.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Choose Music Folder") { showSourcePrompt = false; player.chooseSourceFolder() }
                    .accessibilityIdentifier("lofi-first-source-folder")
                Button("Not now") { player.skipSourcePrompt(); showSourcePrompt = false }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Text("You can choose a folder later from the ••• menu.").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(width: 340)
        }
    }

    private var header: some View {
        HStack {
            Label("Lofi", systemImage: "moon.stars").font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            libraryMenu
        }
    }

    private var libraryMenu: some View {
        Menu {
            Button("Choose Source Folder…", systemImage: "folder.badge.plus", action: player.chooseSourceFolder)
                .accessibilityIdentifier("lofi-choose-source-folder")
            Button("Refresh Library", systemImage: "arrow.clockwise", action: player.reloadSourceFolder)
                .disabled(player.sourceFolder == nil || player.isLoading)
            Button("Show Source Folder", systemImage: "folder", action: player.revealSourceFolder)
                .disabled(player.sourceFolder == nil)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: Circle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Lofi music source")
            .accessibilityIdentifier("lofi-library")
    }

    private var nowPlaying: some View {
        VStack(spacing: 14) {
            Vinyl(spinning: player.isPlaying && player.popupVisible)
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(player.current.title).font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(player.current.artist.isEmpty ? player.sourceFolder?.lastPathComponent ?? "Your local music" : player.current.artist)
                    .font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
            }
            VStack(spacing: 2) {
                Slider(value: Binding(get: { player.duration > 0 ? player.elapsed / player.duration : 0 },
                    set: { player.seek(to: $0) })).accessibilityLabel("Position")
                HStack {
                    Text(Self.time(player.elapsed))
                    Spacer()
                    Text(Self.time(player.duration))
                }.font(.system(size: 10).monospacedDigit()).foregroundStyle(secondary)
            }
            if let message = player.message {
                Text(message).font(.caption).foregroundStyle(Cozy.amber).multilineTextAlignment(.center)
            } else if player.isLoading, !player.isPlaying {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Getting your track ready…").font(.caption).foregroundStyle(secondary)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 13) {
            HStack(spacing: 22) {
                shuffleButton
                control("backward.fill", "Previous") { player.previous() }
                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .offset(x: player.isPlaying ? 0 : 2)
                        .foregroundStyle(Cozy.plum)
                        .frame(width: 58, height: 58)
                        .background(LinearGradient(colors: [Cozy.cream, Cozy.amber], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .shadow(color: Cozy.amber.opacity(0.18), radius: 12, y: 3)
                }.buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play lofi")
                    .accessibilityIdentifier("lofi-play")
                control("forward.fill", "Next") { player.next() }
                Color.clear.frame(width: 28, height: 28)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 10))
                Slider(value: Binding(get: { player.volume }, set: { player.volume = $0 }), in: 0...1)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
            }.foregroundStyle(secondary).padding(.horizontal, 24)
        }
    }

    private var shuffleButton: some View {
        Button { player.setShuffle(!player.shuffle) } label: {
            Image(systemName: "shuffle").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(player.shuffle ? Cozy.amber : secondary)
                .frame(width: 28, height: 28)
                .background(player.shuffle ? Cozy.amber.opacity(0.12) : .clear, in: Circle())
        }.buttonStyle(.plain)
            .help(player.shuffle ? "Shuffle is on: each song plays once per round" : "Shuffle is off")
            .accessibilityLabel(player.shuffle ? "Shuffle on" : "Shuffle off")
            .accessibilityIdentifier("lofi-shuffle")
    }

    private func control(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 32, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var playlist: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Playlist").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(player.shuffle ? "\(player.remaining.count) in this round" : "In order")
                    .font(.system(size: 10)).foregroundStyle(secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(player.tracks.enumerated()), id: \.element.id) { position, track in
                            trackRow(track, position: position).id(track.id)
                        }
                    }
                }.scrollIndicators(.never)
                    .onChange(of: player.index) { _, _ in withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(player.current.id, anchor: .center) } }
                    .onAppear { proxy.scrollTo(player.current.id, anchor: .center) }
            }
        }.frame(maxHeight: .infinity)
    }

    private func trackRow(_ track: LofiTrack, position: Int) -> some View {
        let isCurrent = position == player.index
        return Button { player.play(track: track.id) } label: {
            HStack(spacing: 10) {
                Group {
                    if isCurrent && player.isPlaying { Equalizer(active: player.popupVisible).scaleEffect(0.8) }
                    else { Text(String(format: "%02d", position + 1)).font(.system(size: 10).monospacedDigit()).foregroundStyle(secondary) }
                }.frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 12, weight: isCurrent ? .semibold : .regular)).lineLimit(1)
                    if !track.artist.isEmpty { Text(track.artist).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                Text(Self.time(Double(track.seconds))).font(.system(size: 10).monospacedDigit()).foregroundStyle(secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(isCurrent ? Cozy.amber.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("lofi-track-\(position + 1)")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if player.isLoading { ProgressView().controlSize(.mini); Text("Reading your music folder…") }
            else {
                Image(systemName: "folder")
                Text(player.sourceFolder?.lastPathComponent ?? "Choose a source in the ••• menu").lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(player.tracks.count) tracks")
        }.font(.system(size: 10)).foregroundStyle(secondary)
            .accessibilityHint("Use the top-right menu to choose or refresh your music source folder.")
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(0, seconds)); return String(format: "%d:%02d", total / 60, total % 60)
    }
}
