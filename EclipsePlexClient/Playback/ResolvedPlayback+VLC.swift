import Foundation

extension ResolvedPlayback {
    func vlcConfiguration(
        candidateIndex: Int,
        resumePositionMs overrideMs: Int? = nil
    ) -> VLCVideoPlayer.Configuration {
        let candidate = candidates[candidateIndex]
        let startMs = max(0, overrideMs ?? resumePositionMs ?? 0)
        return VLCVideoPlayer.Configuration(
            url: candidate.url,
            autoPlay: true,
            startSeconds: Duration.milliseconds(startMs),
            rate: .absolute(PlaybackPreferences.loadPlaybackRate()),
            httpHeaderFields: httpHeaderFields
        )
    }
}
