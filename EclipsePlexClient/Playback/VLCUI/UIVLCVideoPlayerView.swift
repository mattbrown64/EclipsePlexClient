import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

public class UIVLCVideoPlayerView: _PlatformView {

    #if os(macOS)
    private lazy var videoContentView: VLCVideoView = makeVideoContentView()
    #else
    private lazy var videoContentView: _PlatformView = makeVideoContentView()
    #endif

    private var configuration: VLCVideoPlayer.Configuration
    private var proxy: VLCVideoPlayer.Proxy?
    private let onTicksUpdated: (Int, VLCVideoPlayer.PlaybackInformation) -> Void
    private let onStateUpdated: (VLCVideoPlayer.State, VLCVideoPlayer.PlaybackInformation) -> Void
    private let loggingInfo: (logger: VLCVideoPlayerLogger, level: VLCVideoPlayer.LoggingLevel)?
    private var currentMediaPlayer: VLCMediaPlayer?

    // Note: necessary as the configuration values have to be set
    //       after streams have been added and playback starts for
    //       at least one tick-changed report. This could cause a
    //       small, noticeable jump when playback starts.
    private var hasSetConfiguration: Bool = false
    private var lastAspectFill: Float = 0
    private var lastPlayerTicks: Int32 = 0
    private var lastPlayerState: VLCMediaPlayerState = .opening

    private var aspectFillScale: CGFloat {
        guard let currentMediaPlayer else { return 1 }
        let videoSize = currentMediaPlayer.videoSize
        let fillSize = CGSize.aspectFill(aspectRatio: videoSize, minimumSize: videoContentView.bounds.size)
        return fillSize.scale(other: videoContentView.bounds.size)
    }

    init(
        configuration: VLCVideoPlayer.Configuration,
        proxy: VLCVideoPlayer.Proxy?,
        onTicksUpdated: @escaping (Int, VLCVideoPlayer.PlaybackInformation) -> Void,
        onStateUpdated: @escaping (VLCVideoPlayer.State, VLCVideoPlayer.PlaybackInformation) -> Void,
        loggingInfo: (VLCVideoPlayerLogger, VLCVideoPlayer.LoggingLevel)?
    ) {
        self.configuration = configuration
        self.proxy = proxy
        self.onTicksUpdated = onTicksUpdated
        self.onStateUpdated = onStateUpdated
        self.loggingInfo = loggingInfo
        super.init(frame: .zero)

        proxy?.videoPlayerView = self

        #if os(macOS)
        layer?.backgroundColor = .clear
        #else
        backgroundColor = .clear
        #endif

        setupVideoContentView()
        setupVLCMediaPlayer(with: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupVideoContentView() {
        addSubview(videoContentView)

        NSLayoutConstraint.activate([
            videoContentView.topAnchor.constraint(equalTo: topAnchor),
            videoContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            videoContentView.leftAnchor.constraint(equalTo: leftAnchor),
            videoContentView.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    func setupVLCMediaPlayer(with newConfiguration: VLCVideoPlayer.Configuration) {
        currentMediaPlayer?.stop()
        currentMediaPlayer = nil

        let media = VLCMedia(url: newConfiguration.url)
        media.addOptions(newConfiguration.options)
        VLCNetworkMediaOptions.apply(
            to: media,
            url: newConfiguration.url,
            headerFields: newConfiguration.httpHeaderFields
        )

        #if os(macOS)
        let newMediaPlayer = VLCMediaPlayer(videoView: videoContentView)
        #else
        let newMediaPlayer = VLCMediaPlayer()
        newMediaPlayer.drawable = videoContentView
        #endif
        newMediaPlayer.media = media
        newMediaPlayer.delegate = self

        if let loggingInfo {
            newMediaPlayer.libraryInstance.debugLogging = true
            newMediaPlayer.libraryInstance.debugLoggingLevel = loggingInfo.level.rawValue.asInt32
            newMediaPlayer.libraryInstance.debugLoggingTarget = self
        }

        for child in newConfiguration.playbackChildren {
            newMediaPlayer.addPlaybackSlave(child.url, type: child.type.asVLCSlaveType, enforce: child.enforce)
        }

        hasSetConfiguration = false
        configuration = newConfiguration
        currentMediaPlayer = newMediaPlayer
        proxy?.mediaPlayer = newMediaPlayer
        lastPlayerTicks = 0
        lastPlayerState = .opening

        if newConfiguration.autoPlay {
            // Defer until the representable has a non-zero frame (see `startPlaybackIfNeeded`).
            DispatchQueue.main.async { [weak self] in
                self?.startPlaybackIfNeeded()
            }
        }
    }

    /// Current playback position for resume / scrobble reporting.
    func playbackPositionSnapshot() -> (positionMs: Int, durationMs: Int) {
        guard let player = currentMediaPlayer, let media = player.media else {
            return (0, 0)
        }
        return (Int(player.time.intValue), Int(media.length.intValue))
    }

    func setAspectFill(with percentage: Float) {
        guard percentage >= 0, percentage <= 1 else { return }
        let scale = 1 + CGFloat(percentage) * (aspectFillScale - 1)
        videoContentView.scale(x: scale, y: scale)

        lastAspectFill = percentage
    }

    #if os(macOS)
    private func makeVideoContentView() -> VLCVideoView {
        let view = VLCVideoView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backColor = .black
        return view
    }
    #else
    private func makeVideoContentView() -> _PlatformView {
        let view = _PlatformView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        return view
    }
    #endif

    /// Start playback once the view is in a window with a real size (SwiftUI sheets layout asynchronously).
    private func startPlaybackIfNeeded() {
        guard configuration.autoPlay, let player = currentMediaPlayer else { return }
        guard window != nil, videoContentView.bounds.width > 1, videoContentView.bounds.height > 1 else { return }

        #if !os(macOS)
        player.drawable = videoContentView
        #endif
        switch player.state {
        case .stopped, .ended, .error:
            player.play()
        case .opening, .buffering, .paused:
            player.play()
        default:
            break
        }
    }

    #if os(macOS)
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startPlaybackIfNeeded()
    }

    public override func layout() {
        super.layout()
        setAspectFill(with: lastAspectFill)
        startPlaybackIfNeeded()
    }
    #else
    override public func layoutSubviews() {
        super.layoutSubviews()
        setAspectFill(with: lastAspectFill)
        startPlaybackIfNeeded()
    }
    #endif
}

// MARK: constructPlaybackInformation

extension UIVLCVideoPlayerView {

    private func constructPlaybackInformation(player: VLCMediaPlayer, media: VLCMedia) -> VLCVideoPlayer.PlaybackInformation {

        let subtitleIndexes = player.videoSubTitlesIndexes as! [Int]
        let subtitleNames = player.videoSubTitlesNames as! [String]

        let audioIndexes = player.audioTrackIndexes as! [Int]
        let audioNames = player.audioTrackNames as! [String]

        let videoIndexes = player.videoTrackIndexes as! [Int]
        let videoNames = player.videoTrackNames as? [String]

        let subtitleTracks = zip(subtitleIndexes, subtitleNames).map { MediaTrack(index: $0, title: $1) }
        let audioTracks = zip(audioIndexes, audioNames).map { MediaTrack(index: $0, title: $1) }
        let videoTracks = zip(videoIndexes, videoNames ?? []).map { MediaTrack(index: $0, title: $1) }

        let currentSubtitleTrack: MediaTrack = subtitleTracks
            .first(where: { $0.index == player.currentVideoSubTitleIndex.asInt })
            .chaining(.init(index: -1, title: "Disable"))
        let currentAudioTrack: MediaTrack = audioTracks
            .first(where: { $0.index == player.currentAudioTrackIndex.asInt })
            .chaining(.init(index: -1, title: "Disable"))
        let currentVideoTrack: MediaTrack = videoTracks
            .first(where: { $0.index == player.currentVideoTrackIndex.asInt })
            .chaining(.init(index: -1, title: "Disable"))

        return VLCVideoPlayer.PlaybackInformation(
            startConfiguration: configuration,
            position: player.position,
            length: media.length.intValue.asInt,
            isSeekable: player.isSeekable,
            playbackRate: player.rate,
            videoSize: player.videoSize,
            currentSubtitleTrack: currentSubtitleTrack,
            currentAudioTrack: currentAudioTrack,
            currentVideoTrack: currentVideoTrack,
            subtitleTracks: subtitleTracks,
            audioTracks: audioTracks,
            videoTracks: videoTracks,
            statistics: .init(stats: media.statistics)
        )
    }
}

// MARK: VLCMediaPlayerDelegate

extension UIVLCVideoPlayerView: VLCMediaPlayerDelegate {

    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let player = aNotification.object as! VLCMediaPlayer
        let currentTicks = player.time.intValue
        let playbackInformation = constructPlaybackInformation(player: player, media: player.media!)

        if !hasSetConfiguration {
            setConfigurationValues(
                with: player,
                from: configuration
            )

            hasSetConfiguration = true
        } else {
            onTicksUpdated(currentTicks.asInt, playbackInformation)
        }

        // Set playing state
        if lastPlayerState != .playing,
           abs(currentTicks - lastPlayerTicks) >= 200
        {
            onStateUpdated(.playing, playbackInformation)
            lastPlayerState = .playing
            lastPlayerTicks = currentTicks
        }

        // Replay
        if configuration.replay,
           lastPlayerState == .playing,
           abs(player.media!.length.intValue - currentTicks) <= 500
        {
            configuration.autoPlay = true
            configuration.startTime = .ticks(0)
            setupVLCMediaPlayer(with: configuration)
        }
    }

    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        let player = aNotification.object as! VLCMediaPlayer
        guard player.state != lastPlayerState else { return }
        guard let media = player.media else { return }

        let wrappedState = VLCVideoPlayer.State(rawValue: player.state.rawValue) ?? .error
        let playbackInformation = constructPlaybackInformation(player: player, media: media)

        onStateUpdated(wrappedState, playbackInformation)
        lastPlayerState = player.state
    }

    private func setConfigurationValues(with player: VLCMediaPlayer, from configuration: VLCVideoPlayer.Configuration) {

        if configuration.startTime.asTicks != 0 {
            player.time = VLCTime(int: configuration.startTime.asTicks.asInt32)
        }

        let defaultPlayerSpeed = player.rate(from: configuration.rate)
        // `fastForward(atRate:)` is for seek-style FF; on macOS it breaks normal 1x playback.
        player.rate = defaultPlayerSpeed

        if configuration.aspectFill {
            videoContentView.scale(x: aspectFillScale, y: aspectFillScale)
        } else {
            videoContentView.apply(transform: .identity)
        }

        let defaultSubtitleTrackIndex = player.subtitleTrackIndex(from: configuration.subtitleIndex)
        player.currentVideoSubTitleIndex = defaultSubtitleTrackIndex.asInt32

        let defaultAudioTrackIndex = player.audioTrackIndex(from: configuration.audioIndex)
        player.currentAudioTrackIndex = defaultAudioTrackIndex.asInt32

        player.setSubtitleSize(configuration.subtitleSize)
        player.setSubtitleFont(configuration.subtitleFont)
        player.setSubtitleColor(configuration.subtitleColor)
    }
}

// MARK: VLCLibraryLogReceiverProtocol

extension UIVLCVideoPlayerView: VLCLibraryLogReceiverProtocol {

    public func handleMessage(_ message: String, debugLevel level: Int32) {
        guard let loggingInfo, level >= loggingInfo.level.rawValue else { return }
        let level = VLCVideoPlayer.LoggingLevel(rawValue: level.asInt) ?? .info
        loggingInfo.logger.vlcVideoPlayer(didLog: message, at: level)
    }
}
