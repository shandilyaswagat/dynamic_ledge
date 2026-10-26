import SwiftUI

/// Leading and trailing views either side of the empty middle, like ActivityKit's compact form.
struct CompactView: View {
    let model: IslandModel
    let kind: ActivityKind
    let size: CGSize
    /// Middle width kept clear for the camera.
    let cameraGap: CGFloat
    @Environment(\.notchScale) private var sizeScale

    var body: some View {
        let scale = CompactScale(height: size.height, size: sizeScale)
        let edge = scale.padding + 2
        // Each side gets the space between the outer edge and the camera, minus a little air.
        let side = max(0, (size.width - cameraGap) / 2 - edge - (cameraGap > 0 ? 4 : 3))
        HStack(spacing: 0) {
            leading(scale)
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            trailing(scale)
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, edge)
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func leading(_ scale: CompactScale) -> some View {
        switch kind {
        case .nowPlaying:
            ArtworkView(
                artwork: model.nowPlaying.artwork,
                fallbackIcon: model.nowPlaying.appIcon,
                size: scale.icon,
                cornerRadius: scale.icon * 0.28
            )
            .accessibilityLabel(Text(model.nowPlaying.info?.title ?? ""))
        case .timer:
            let mode = model.timer.timer?.mode ?? .plain
            Image(systemName: mode.symbol)
                .font(.system(size: scale.fontSize + 1, weight: .semibold))
                .foregroundStyle(mode.tint)
                .accessibilityLabel(Text(mode.title))
        case .stopwatch:
            Image(systemName: "stopwatch.fill")
                .font(.system(size: scale.fontSize + 1, weight: .semibold))
                .foregroundStyle(NotchColor.orange)
                .accessibilityLabel(Text("Stopwatch"))
        case .call:
            if let session = model.calls.session, !session.isCall {
                AppIconView(icon: model.calls.appIcon, symbol: "mic.fill", tint: NotchColor.orange, size: scale.icon)
                    .accessibilityLabel(Text(session.appName))
            } else {
                Image(systemName: model.calls.session?.usesCamera == true ? "video.fill" : "phone.fill")
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .foregroundStyle(NotchColor.green)
                    .accessibilityLabel(Text("On Call"))
            }
        case .stats:
            StatsCompactValue(caption: "MEM", share: model.stats.snapshot.memoryTotal > 0 ? model.stats.snapshot.memory : nil, level: model.stats.snapshot.memoryPressure, fontSize: scale.fontSize)
        }
    }

    @ViewBuilder
    private func trailing(_ scale: CompactScale) -> some View {
        switch kind {
        case .nowPlaying:
            WaveformBars(
                color: NotchColor.accent(model.nowPlaying.accent),
                isPlaying: model.nowPlaying.info?.isPlaying == true
            )
            .frame(width: scale.icon * 0.9, height: scale.icon * 0.78)
        case .timer:
            if let timer = model.timer.timer {
                CountdownText(timer: timer)
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(timer.mode.tint.opacity(timer.isPaused ? 0.6 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .stopwatch:
            let isRunning = model.stopwatch.stopwatch?.isRunning == true
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimeFormatting.clock(model.stopwatch.elapsed(at: context.date)))
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.orange.opacity(isRunning ? 1 : 0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .call:
            if let session = model.calls.session {
                Text(session.startDate, style: .timer)
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(session.isCall ? NotchColor.green : NotchColor.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .stats:
            StatsCompactValue(caption: "CPU", share: model.stats.hasReading ? model.stats.snapshot.cpu : nil, fontSize: scale.fontSize, alignment: .trailing)
        }
    }
}

/// Content of the detached bubble for the second activity.
struct MinimalView: View {
    let model: IslandModel
    let kind: ActivityKind
    let diameter: CGFloat

    var body: some View {
        let inner = (diameter * 0.64).rounded()
        Group {
            switch kind {
            case .nowPlaying:
                if model.nowPlaying.artwork != nil || model.nowPlaying.appIcon != nil {
                    ArtworkView(artwork: model.nowPlaying.artwork, fallbackIcon: model.nowPlaying.appIcon, size: inner, cornerRadius: inner / 2)
                } else {
                    WaveformBars(color: NotchColor.accent(model.nowPlaying.accent), isPlaying: model.nowPlaying.info?.isPlaying == true)
                        .frame(width: inner * 0.7, height: inner * 0.6)
                }
            case .timer:
                TimerRing(model: model, diameter: inner)
            case .stopwatch:
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(NotchColor.orange)
            case .call:
                Image(systemName: model.calls.session?.usesCamera == true ? "video.fill" : "phone.fill")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(model.calls.session?.isCall == false ? NotchColor.orange : NotchColor.green)
            case .stats:
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(NotchColor.green)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Ring that empties as the timer runs, in the timer's colour.
private struct TimerRing: View {
    let model: IslandModel
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = model.timer.timer?.progress(at: context.date) ?? 0
            let mode = model.timer.timer?.mode ?? .plain
            ZStack {
                Circle().stroke(mode.tint.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(mode.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: mode.symbol)
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(mode.tint)
            }
            .frame(width: diameter, height: diameter)
        }
    }
}
