import AVFoundation
import AppKit
import MediaPlayer
import Observation
import VehlaDockWidgetSDK

@MainActor @Observable
final class LofiPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var tracks: [LofiTrack] = []
    private(set) var sourceFolder: URL?
    private(set) var isLoading = false
    private(set) var shouldPromptSource = false
    @ObservationIgnored private var bookmark: Data?
    @ObservationIgnored private var promptShown = false
    @ObservationIgnored private var sourceAccess = false
    @ObservationIgnored private var sourceRequestID = UUID()
    private(set) var index: Int
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var message: String?
    private(set) var shuffle: Bool
    private(set) var remainingRevision = 0
    var remaining: [Int] { _ = remainingRevision; return bag.remaining }
    var theme: VehlaDockWidgetTheme?
    var popupVisible = false
    var surfaceVisible = true
    var volume: Double {
        didSet { player?.volume = Float(volume); persist() }
    }
    @ObservationIgnored private var bag = LofiShuffleBag(count: 0) {
        didSet { remainingRevision += 1; persist() }
    }
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var context: VehlaDockWidgetContext?
    @ObservationIgnored private var history: [Int] = []
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var remoteCommands: [MPRemoteCommand] = []

    enum RemoteAction: Sendable {
        case play, pause, toggle, next, previous
        case seek(Double), skip(Double)
    }

    init(directory: URL, context: VehlaDockWidgetContext? = nil) {
        self.directory = directory; self.context = context
        let saved = LofiPreferences.load(from: directory)
        index = max(0, saved.index)
        volume = saved.volume.isFinite ? min(max(saved.volume, 0), 1) : 0.7
        shuffle = saved.shuffle
        bookmark = saved.sourceBookmark
        promptShown = saved.sourcePromptShown ?? false
        super.init()
        theme = context?.theme
        if let bookmark {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale { self.bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
                loadSource(url, keepingIndex: true)
            } catch { message = "Your music folder is unavailable. Choose it again from the ••• menu." }
        } else { shouldPromptSource = !promptShown }
    }
    var current: LofiTrack { tracks.indices.contains(index) ? tracks[index] : .empty }
    private func persist() {
        LofiPreferences(index: index, shuffle: shuffle, volume: volume, remaining: bag.remaining,
            sourceBookmark: bookmark, sourcePromptShown: promptShown).save(to: directory)
    }
    func skipSourcePrompt() { promptShown = true; shouldPromptSource = false; persist() }
    func chooseSourceFolder() {
        skipSourcePrompt()
        let panel = NSOpenPanel()
        panel.title = "Choose your music folder"
        panel.message = "Lofi plays audio from this folder and its subfolders. Your files stay in place."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.directoryURL = sourceFolder
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.selectSourceFolder(url)
        }
    }
    func selectSourceFolder(_ url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmark = data; promptShown = true; shouldPromptSource = false
            loadSource(url); persist()
        } catch { message = "Couldn't remember this folder. Please choose it again." }
    }
    func reloadSourceFolder() { if let sourceFolder { loadSource(sourceFolder, keepingIndex: true) } }
    func revealSourceFolder() { if let sourceFolder { NSWorkspace.shared.open(sourceFolder) } }
    func waitForSourceScan() async { await scanTask?.value }
    private func loadSource(_ url: URL, keepingIndex: Bool = false) {
        pause(); releaseMediaControls(); player = nil; scanTask?.cancel()
        if sourceAccess, let sourceFolder { sourceFolder.stopAccessingSecurityScopedResource() }
        sourceFolder = url; sourceAccess = url.startAccessingSecurityScopedResource()
        tracks = []; bag = LofiShuffleBag(count: 0); history = []; elapsed = 0; duration = 0
        if !keepingIndex { index = 0 }
        isLoading = true; message = nil
        let token = UUID(); sourceRequestID = token
        scanTask = Task { [weak self] in
            do {
                let tracks = try await LofiLibrary.scan(url)
                guard !Task.isCancelled, let self, self.sourceRequestID == token else { return }
                self.tracks = tracks; self.index = tracks.indices.contains(self.index) ? self.index : 0
                self.bag = LofiShuffleBag(count: tracks.count)
                if self.shuffle { self.bag.refill(excluding: self.index) }
                self.duration = Double(self.current.seconds)
                self.message = tracks.isEmpty ? "No supported audio files in this folder. Choose another from the ••• menu." : nil
                self.isLoading = false; self.scanTask = nil; self.persist()
            } catch {
                guard !Task.isCancelled, let self, self.sourceRequestID == token else { return }
                self.isLoading = false; self.scanTask = nil
                self.message = "Couldn't read your music folder. Reconnect the drive or choose a folder again."
            }
        }
    }
    func togglePlay() { (isPlaying || playbackTask != nil) ? pause() : play() }
    func play() {
        guard !tracks.isEmpty else { message = "Choose a music folder from the ••• menu to start listening."; return }
        message = nil
        if let player, !isPlaying, player.url == current.url { startPlayback(player); return }
        startTrack(at: index)
    }
    func pause() {
        requestID = UUID(); playbackTask?.cancel(); playbackTask = nil
        player?.pause(); isPlaying = false; stopTicker()
        if let player { elapsed = player.currentTime }
        updateNowPlaying()
    }
    func next() { guard !tracks.isEmpty else { return }; remember(index); startTrack(at: nextIndex()) }
    func previous() {
        guard !tracks.isEmpty else { return }
        if let player, player.currentTime > 4 {
            player.currentTime = 0; elapsed = 0
            if !isPlaying { startPlayback(player) } else { updateNowPlaying() }
            return
        }
        if shuffle {
            guard let last = history.popLast() else { return }
            bag.markPlayed(last); bag.putBack(index); startTrack(at: last)
        } else { startTrack(at: (index - 1 + tracks.count) % tracks.count) }
    }
    func play(track id: String) {
        guard let position = tracks.firstIndex(where: { $0.id == id }) else { return }
        if position == index { play(); return }
        remember(index); bag.markPlayed(position); startTrack(at: position)
    }
    func setShuffle(_ on: Bool) {
        shuffle = on
        if on { bag.refill(excluding: index) } else { bag.reset([]) }
        persist()
    }
    private func remember(_ position: Int) { history.append(position); if history.count > 60 { history.removeFirst() } }
    private func nextIndex() -> Int { shuffle ? bag.next(after: index) : (index + 1) % tracks.count }
    func seek(to fraction: Double) {
        guard let player, duration > 0, fraction.isFinite else { return }
        player.currentTime = min(max(fraction, 0), 1) * duration; elapsed = player.currentTime
        updateNowPlaying()
    }
    private func startTrack(at position: Int) {
        guard tracks.indices.contains(position) else { return }
        playbackTask?.cancel(); player?.stop(); player = nil; isPlaying = false; stopTicker()
        let token = UUID(); requestID = token
        let track = tracks[position]; index = position; message = nil; elapsed = 0; duration = Double(track.seconds); persist()
        updateNowPlaying()
        playbackTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.requestID == token else { return }
            do {
                let next = try AVAudioPlayer(contentsOf: track.url)
                next.delegate = self; next.volume = Float(self.volume); next.prepareToPlay()
                self.player = next; self.duration = next.duration; self.startPlayback(next)
            } catch {
                self.message = "“\(track.title)” couldn't be played. The file may be unavailable or unsupported."
                self.isPlaying = false; self.releaseMediaControls()
            }
            self.playbackTask = nil
        }
    }
    private func startPlayback(_ player: AVAudioPlayer) {
        isPlaying = player.play()
        if isPlaying { registerMediaControls(); startTicker(); updateNowPlaying() }
        else { message = "This track couldn't start playing."; releaseMediaControls() }
    }

    private func registerMediaControls() {
        guard remoteCommands.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        remoteCommands = [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand,
            center.skipForwardCommand, center.skipBackwardCommand]
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        for command in remoteCommands {
            command.isEnabled = true
            command.addTarget(self, action: #selector(receiveRemoteCommand(_:)))
        }
    }

    // Remote events may arrive off the main thread. Finish the action before returning
    // its status, so rapid play/pause clicks cannot outlive the playback session.
    @objc nonisolated private func receiveRemoteCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        let center = MPRemoteCommandCenter.shared()
        let action: RemoteAction
        switch event.command {
        case center.playCommand: action = .play
        case center.pauseCommand: action = .pause
        case center.togglePlayPauseCommand: action = .toggle
        case center.nextTrackCommand: action = .next
        case center.previousTrackCommand: action = .previous
        case center.changePlaybackPositionCommand:
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            action = .seek(event.positionTime)
        case center.skipForwardCommand, center.skipBackwardCommand:
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            action = .skip(event.command == center.skipForwardCommand ? event.interval : -event.interval)
        default: return .commandFailed
        }
        if Thread.isMainThread { return MainActor.assumeIsolated { handleRemoteAction(action) } }
        return DispatchQueue.main.sync { self.handleRemoteAction(action) }
    }

    func handleRemoteAction(_ action: RemoteAction) -> MPRemoteCommandHandlerStatus {
        guard !remoteCommands.isEmpty, tracks.indices.contains(index) else { return .noActionableNowPlayingItem }
        switch action {
        case .play: if !isPlaying && playbackTask == nil { play() }
        case .pause: pause()
        case .toggle: togglePlay()
        case .next: next()
        case .previous: previous()
        case .seek(let seconds):
            guard player != nil, duration > 0, seconds.isFinite else { return .commandFailed }
            seek(to: seconds / duration)
        case .skip(let seconds):
            guard let player, duration > 0, seconds.isFinite else { return .commandFailed }
            seek(to: (player.currentTime + seconds) / duration)
        }
        return .success
    }

    private func updateNowPlaying() {
        guard !remoteCommands.isEmpty, tracks.indices.contains(index) else { return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist.isEmpty ? "Lofi" : current.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        // Pausing retains the item and command targets so headphones can resume Lofi.
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func releaseMediaControls() {
        guard !remoteCommands.isEmpty else { return }
        // Remove only our targets: other audio widgets share this process's center.
        for command in remoteCommands { command.removeTarget(self) }
        remoteCommands = []
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = .stopped
        center.nowPlayingInfo = nil
    }
    func setVisibility(_ phase: VehlaDockWidgetVisibilityPhase) {
        surfaceVisible = phase != .hidden; popupVisible = phase == .popup
        if surfaceVisible && isPlaying { startTicker() } else { stopTicker() }
        // Music continues when the popup closes; timers and animations do not.
        if surfaceVisible, let player { elapsed = player.currentTime }
    }
    private func startTicker() {
        stopTicker(); guard surfaceVisible else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, let player = self.player else { return }; self.elapsed = player.currentTime }
        }
        ticker = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity, self.isPlaying else { return }
            self.isPlaying = false; self.stopTicker(); self.next()
        }
    }
    func shutdown() {
        requestID = UUID(); sourceRequestID = UUID()
        playbackTask?.cancel(); playbackTask = nil
        scanTask?.cancel(); scanTask = nil
        player?.stop(); player = nil; isPlaying = false; stopTicker()
        releaseMediaControls()
        if sourceAccess, let sourceFolder { sourceFolder.stopAccessingSecurityScopedResource(); sourceAccess = false }
    }
}
