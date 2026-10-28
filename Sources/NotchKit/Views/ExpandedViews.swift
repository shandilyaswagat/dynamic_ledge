import SwiftUI

// All sizes below are the Large design; `notchScale` shrinks them for Medium and Small.

// MARK: Now Playing

struct NowPlayingExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let service = model.nowPlaying
        VStack(spacing: 0) {
            if let other = service.selectedSource {
                OtherSourceView(service: service, source: other)
            } else {
                current
            }
            if !service.otherSources.isEmpty {
                MediaSourceSwitcher(service: service)
                    .frame(height: IslandMetrics.ContentHeight.mediaSwitcher * s)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var current: some View {
        let service = model.nowPlaying
        let info = service.info
        let accent = NotchColor.accent(service.accent)
        VStack(spacing: 0) {
            HStack(spacing: 12 * s) {
                Button { service.openSourceApp() } label: {
                    ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: 56 * s, cornerRadius: 13 * s)
                }
                .buttonStyle(PressableButtonStyle())
                .help(service.appName.map { "Open \($0)" } ?? "")
                .accessibilityLabel(Text(service.appName.map { "Open \($0)" } ?? "Open player"))

                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(info?.title ?? "")
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                        .font(.system(size: 13 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                WaveformBars(color: accent, isPlaying: info?.isPlaying == true)
                    .frame(width: 20 * s, height: 18 * s)
            }

            // Exactly ContentHeight.lyrics taller: 26 for the line, 8 above it, and 4 less above
            // the progress bar.
            let showsLyrics = model.showsLyrics
            if showsLyrics, let lyrics = model.lyrics.current {
                LyricsLine(lyrics: lyrics, service: service, size: 14 * s)
                    .frame(height: 26 * s)
                    .padding(.top, 8 * s)
                    .transition(.opacity)
            }

            ProgressRow(service: service)
                .padding(.top, (showsLyrics ? 10 : 14) * s)

            HStack(spacing: 30 * s) {
                GlyphButton(symbol: "backward.fill", size: 19 * s, label: "Previous Track") { service.previousTrack() }
                GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: 27 * s, label: info?.isPlaying == true ? "Pause" : "Play") {
                    service.togglePlayPause()
                }
                GlyphButton(symbol: "forward.fill", size: 19 * s, label: "Next Track") { service.nextTrack() }
            }
            .padding(.top, 4 * s)
        }
        .padding(.horizontal, 22 * s)
        .frame(maxHeight: .infinity)
    }
}

/// The line of the song being sung now, sliding up as the next one starts. A gap between
/// lines shows a note.
struct LyricsLine: View {
    let lyrics: SyncedLyrics
    let service: NowPlayingService
    var size: CGFloat
    var alignment: Alignment = .center

    var body: some View {
        let info = service.info
        TimelineView(.animation(minimumInterval: 0.2, paused: info?.isPlaying != true)) { context in
            // A touch early, so a line appears as it's sung rather than just after.
            let index = info?.elapsed(at: context.date).flatMap { lyrics.index(at: $0 + 0.3) }
            let text = index.map { lyrics.lines[$0].text } ?? ""
            ZStack {
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(text.isEmpty ? NotchColor.secondaryText : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .id(index ?? -1)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .clipped()
            .animation(.smooth(duration: 0.35), value: index)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Lyrics"))
    }
}

private struct ProgressRow: View {
    let service: NowPlayingService
    @State private var scrubProgress: Double?
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        // Only ticks while playing; a paused track has nothing to update.
        TimelineView(.animation(minimumInterval: 0.5, paused: info?.isPlaying != true)) { context in
            let duration = info?.duration
            let live = info?.elapsed(at: context.date)
            let elapsed = scrubProgress.flatMap { progress in duration.map { $0 * progress } } ?? live ?? 0
            let progress = scrubProgress ?? info?.progress(at: context.date)
            HStack(spacing: 10 * s) {
                Text(TimeFormatting.clock(elapsed))
                    .frame(width: 40 * s, alignment: .leading)
                ScrubBar(progress: progress ?? 0, isEnabled: duration != nil) { value, ended in
                    scrubProgress = ended ? nil : value
                    if ended, let duration {
                        service.seek(to: value * duration)
                    }
                }
                Text(duration.map { TimeFormatting.remaining(elapsed: elapsed, duration: $0) } ?? "--:--")
                    .frame(width: 44 * s, alignment: .trailing)
            }
            .font(.system(size: 11 * s, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(NotchColor.secondaryText)
        }
    }
}

struct ScrubBar: View {
    var progress: Double
    var isEnabled: Bool
    /// A round handle at the play position, like the elongated layout's music widget.
    var knob = false
    var onScrub: (Double, Bool) -> Void
    @State private var isDragging = false
    @Environment(\.notchScale) private var s

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white).frame(width: width * clamped)
            }
            .frame(height: (knob ? 4 : (isDragging ? 8 : 5)) * s)
            .overlay(alignment: .leading) {
                if knob {
                    Circle()
                        .fill(Color.white)
                        .frame(width: (isDragging ? 13 : 10) * s, height: (isDragging ? 13 : 10) * s)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: width * clamped - (isDragging ? 6.5 : 5) * s)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isDragging = true
                        onScrub(min(max(value.location.x / width, 0), 1), false)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        isDragging = false
                        onScrub(min(max(value.location.x / width, 0), 1), true)
                    }
            )
            .animation(.spring(duration: 0.25, bounce: 0.3), value: isDragging)
        }
        .frame(height: 14 * s)
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    }
}

// MARK: Call

struct CallExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        if let session = model.calls.session {
            let tint = session.isCall ? NotchColor.green : NotchColor.orange
            VStack(spacing: 4 * s) {
                HStack(spacing: 12 * s) {
                    // The app's icon brings its window forward.
                    Button {
                        model.calls.showApp()
                        model.collapse()
                    } label: {
                        AppIconView(icon: model.calls.appIcon, symbol: session.isCall ? "phone.fill" : "mic.fill", tint: tint, size: 46 * s)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Show \(session.appName)")
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(session.appName)
                            .font(.system(size: 15 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 6 * s) {
                            Text(session.isCall ? "On Call" : "Using Microphone")
                            Text(session.startDate, style: .timer)
                                .monospacedDigit()
                        }
                        .font(.system(size: 13 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8 * s)
                    if session.usesCamera {
                        Image(systemName: "video.fill")
                            .font(.system(size: 12 * s, weight: .semibold))
                            .foregroundStyle(NotchColor.green)
                            .accessibilityLabel(Text("Camera in use"))
                    }
                    // Mutes the Mac's microphone, so it works whatever app the call is in.
                    if model.microphone.canMute {
                        let muted = model.microphone.isMuted
                        CircleButton(
                            symbol: muted ? "mic.slash.fill" : "mic.fill",
                            size: 44 * s,
                            foreground: muted ? .white : NotchColor.orange,
                            background: muted ? NotchColor.red : NotchColor.orange.opacity(0.22),
                            label: muted ? "Unmute Microphone" : "Mute Microphone"
                        ) { model.microphone.toggle() }
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12 * s, weight: .semibold))
                            .foregroundStyle(NotchColor.orange)
                            .accessibilityLabel(Text("Microphone in use"))
                    }
                    if model.calls.canHangUp {
                        CircleButton(symbol: "phone.down.fill", size: 44 * s, foreground: .white, background: NotchColor.red, label: "Hang Up") {
                            Task { @MainActor in
                                if await model.calls.hangUp() == .sent { model.collapse() }
                            }
                        }
                        .help(CallHangup.shortcut(for: session.bundleIdentifier)?.asksToConfirm == true
                              ? "Leave the call (\(session.appName) asks you to confirm)"
                              : "Hang up")
                    } else {
                        CircleButton(symbol: "arrow.up.forward", size: 44 * s, foreground: .white, background: tint, label: "Show \(session.appName)") {
                            model.calls.showApp()
                            model.collapse()
                        }
                    }
                }
                if let message = model.calls.hangUpMessage {
                    Text(message)
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20 * s)
        }
    }
}

// MARK: Several apps playing

/// One button per playing app, like the iPhone's activity switcher: the one shown is white.
private struct MediaSourceSwitcher: View {
    let service: NowPlayingService
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            SourceButton(
                name: service.appName ?? String(localized: "Now Playing"),
                icon: service.appIcon,
                isSelected: service.selectedSourceID == nil
            ) { withAnimation(.spring(duration: 0.3, bounce: 0.15)) { service.selectedSourceID = nil } }
            ForEach(service.otherSources) { source in
                SourceButton(name: source.name, icon: source.icon, isSelected: service.selectedSourceID == source.id) {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { service.selectedSourceID = source.id }
                }
            }
        }
        .padding(.horizontal, 22 * s)
        .padding(.top, 6 * s)
    }
}

private struct SourceButton: View {
    let name: String
    let icon: NSImage?
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * s) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16 * s, height: 16 * s)
                }
                Text(name)
                    .font(.system(size: 12.5 * s, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 28 * s)
            .background(
                RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What another app is playing. macOS only lets the notch control the app it calls "now
/// playing", so this one offers to open the app instead of play controls.
private struct OtherSourceView: View {
    let service: NowPlayingService
    let source: MediaSource
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12 * s) {
                ArtworkView(artwork: source.artwork, fallbackIcon: source.icon, size: 56 * s, cornerRadius: 13 * s)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(source.info.title)
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(source.info.artist.isEmpty ? source.name : source.info.artist)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                WaveformBars(color: NotchColor.accent(source.accent), isPlaying: true)
                    .frame(width: 20 * s, height: 18 * s)
            }
            Button {
                service.open(source)
            } label: {
                Label("Open \(source.name)", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16 * s)
                    .frame(height: 32 * s)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 16 * s)
        }
        .padding(.horizontal, 22 * s)
        .frame(maxHeight: .infinity)
    }
}
