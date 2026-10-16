import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var station: RadioStation?

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private let player = AVPlayer()
    // The player's own change notifications drive the state. A 0.25 s timer used to write every property four
    // times a second, and each @Published write redraws every tile watching the player, even when nothing changed.
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var remoteTargets: [Any] = []
    /// What macOS was last told is playing, so it's only told again when that changes.
    private var publishedNowPlaying: (name: String, rate: Int)?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        setupRemoteCommands()
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronizeState() }
        }
    }

    func shutdown() {
        statusObserver?.invalidate()
        statusObserver = nil
        itemObserver?.invalidate()
        itemObserver = nil
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        let commands = MPRemoteCommandCenter.shared()
        remoteTargets.forEach {
            commands.playCommand.removeTarget($0)
            commands.pauseCommand.removeTarget($0)
            commands.togglePlayPauseCommand.removeTarget($0)
            commands.nextTrackCommand.removeTarget($0)
            commands.previousTrackCommand.removeTarget($0)
        }
        remoteTargets = []
        stop()
    }

    func play(_ station: RadioStation) {
        guard let url = URL(string: station.url_resolved) else {
            errorMessage = "This station has an invalid stream address."
            return
        }

        if self.station?.url_resolved != station.url_resolved {
            if let failedObserver {
                NotificationCenter.default.removeObserver(failedObserver)
            }
            self.station = station
            errorMessage = nil
            isLoading = true
            let item = AVPlayerItem(url: url)
            itemObserver = item.observe(\.status, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            }
            failedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription ?? "Unable to play this station."
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if errorMessage != message { errorMessage = message }
                    if isLoading { isLoading = false }
                    if isPlaying { isPlaying = false }
                    updateNowPlaying()
                }
            }
            player.replaceCurrentItem(with: item)
        }
        player.play()
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying {
            pause()
        } else if let station {
            play(station)
        }
    }

    func pause() {
        player.pause()
        synchronizeState()
    }

    func stop() {
        itemObserver?.invalidate()
        itemObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        station = nil
        if isPlaying { isPlaying = false }
        if isLoading { isLoading = false }
        updateNowPlaying()
    }

    func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    /// Reads the player and writes only what changed, so watching views redraw only on a real change.
    private func synchronizeState() {
        let playing = player.timeControlStatus == .playing
        let loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if isPlaying != playing { isPlaying = playing }
        if isLoading != loading { isLoading = loading }
        if let itemError = player.currentItem?.error, errorMessage != itemError.localizedDescription {
            errorMessage = itemError.localizedDescription
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let station else {
            if publishedNowPlaying != nil {
                publishedNowPlaying = nil
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
            return
        }
        let rate = isPlaying ? 1 : 0
        if let published = publishedNowPlaying, published.name == station.name, published.rate == rate { return }
        publishedNowPlaying = (station.name, rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "Live Radio",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0,
        ]
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true

        remoteTargets.append(commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let station = self.station else { return }
                self.play(station)
            }
            return .success
        })
        remoteTargets.append(commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        })
        remoteTargets.append(commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.toggle() }
            return .success
        })
        remoteTargets.append(commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNext?() }
            return .success
        })
        remoteTargets.append(commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPrevious?() }
            return .success
        })
    }
}
