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
    private var stateTimer: Timer?
    private var failedObserver: NSObjectProtocol?
    private var remoteTargets: [Any] = []

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        setupRemoteCommands()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.synchronizeState() }
        }
    }

    func shutdown() {
        stateTimer?.invalidate()
        stateTimer = nil
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
            failedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription ?? "Unable to play this station."
                Task { @MainActor [weak self] in
                    self?.errorMessage = message
                    self?.isLoading = false
                    self?.isPlaying = false
                    self?.updateNowPlaying()
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
        player.pause()
        player.replaceCurrentItem(with: nil)
        station = nil
        isPlaying = false
        isLoading = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    private func synchronizeState() {
        isPlaying = player.timeControlStatus == .playing
        isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if let itemError = player.currentItem?.error {
            errorMessage = itemError.localizedDescription
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let station else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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
