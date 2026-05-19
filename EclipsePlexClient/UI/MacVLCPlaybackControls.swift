#if os(macOS)
import SwiftUI

/// Transport bar for `MacVLCPlaybackController`.
struct MacVLCPlaybackControls: View {
    @ObservedObject var controller: MacVLCPlaybackController
    let onClose: () -> Void

    @State private var scrubberMs: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressRow
            transportRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .onChange(of: controller.positionMs) { _, position in
            if !isScrubbing {
                scrubberMs = Double(position)
            }
        }
        .onAppear {
            scrubberMs = Double(controller.positionMs)
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(controller.formattedPosition)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: $scrubberMs,
                in: 0 ... max(Double(controller.durationMs), 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        controller.seek(toMs: Int(scrubberMs))
                    }
                }
            )
            .disabled(controller.durationMs <= 0)

            Text(controller.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
        .padding(.bottom, 10)
    }

    private var transportRow: some View {
        HStack(spacing: 16) {
            Button {
                controller.skip(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
            }
            .help("Back 10 seconds")

            Button(action: controller.togglePlayPause) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .help(controller.isPlaying ? "Pause" : "Play")

            Button {
                controller.skip(by: 10)
            } label: {
                Image(systemName: "goforward.10")
            }
            .help("Forward 10 seconds")

            Spacer()

            Button(action: controller.toggleMute) {
                Image(systemName: controller.isMuted || controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(controller.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { Double(controller.volume) },
                    set: { controller.setVolume(Int($0)) }
                ),
                in: 0 ... 100
            )
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}
#endif
