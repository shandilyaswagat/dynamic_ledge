import SwiftUI

// The elongated layout: Home becomes one long, short row of widgets across the top of the
// screen, split by hairlines, that you scroll sideways through. In order: music, the camera
// mirror, this week's calendar, a formatted note, a wheel timer, a to-do list and, when it's
// on, Stats. Blue is the accent throughout, and each widget works
// right where it is: play, scrub, join a call, type, tick off, start a timer.

/// Home in the elongated layout.
struct ElongatedHomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let widgets = Self.widgets(for: model)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1)
                            .padding(.vertical, 10 * s)
                    }
                    view(for: widget)
                        .frame(width: widget.width * s)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, index == 0 ? 0 : 16 * s)
                        .padding(.trailing, index == widgets.count - 1 ? 0 : 16 * s)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .scrollTargetLayout()
            .animation(.smooth(duration: 0.3), value: widgets)
        }
        .scrollIndicators(.never)
        // Settles on a widget's edge instead of stopping halfway through one.
        .scrollTargetBehavior(.viewAligned)
        // Widgets running past either end fade out instead of being cut off. The margins keep
        // the fade over empty space when the row sits at either end.
        .contentMargins(.horizontal, 14 * s, for: .scrollContent)
        // Reaches into the nook's side padding, so the widgets stay where they were.
        .padding(.horizontal, -14 * s)
        .mask(EdgeFade(width: 14 * s))
        .padding(.bottom, 2 * s)
        .overlay {
            if widgets.isEmpty {
                Text("Nothing live right now")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
    }

    enum Widget: Hashable {
        case music, mirror, calendar, notes, timer, todos, stats, aiUsage

        /// Width before Small / Medium / Large scaling.
        var width: CGFloat {
            switch self {
            case .music: 290
            case .mirror: 96
            case .calendar: 300
            case .notes: 230
            case .timer: 250
            case .todos: 230
            case .stats: 210
            case .aiUsage: 220
            }
        }
    }

    /// The widgets that are switched on, in reading order.
    static func widgets(for model: IslandModel) -> [Widget] {
        var widgets: [Widget] = []
        if model.homeHasMedia { widgets.append(.music) }
        if model.settings.mirrorEnabled { widgets.append(.mirror) }
        if model.settings.calendarEnabled { widgets.append(.calendar) }
        if model.settings.notesEnabled { widgets.append(.notes) }
        if model.settings.timerEnabled { widgets.append(.timer) }
        widgets.append(.todos)
        if model.settings.statsEnabled { widgets.append(.stats) }
        if model.settings.aiUsageEnabled && model.settings.aiUsageShowHomeWidget && !model.aiUsage.visibleUsages(selected: model.settings.selectedAIProviders).isEmpty { widgets.append(.aiUsage) }
        return widgets
    }

    @ViewBuilder
    private func view(for widget: Widget) -> some View {
        switch widget {
        case .music: MusicWidget(service: model.nowPlaying)
        case .mirror: MirrorWidget(model: model)
        case .calendar: CalendarWidget(model: model)
        case .notes: NotesWidget(model: model)
        case .timer: TimerWidget(model: model)
        case .todos: TodosWidget(model: model)
        case .stats: StatsWidget(model: model)
        case .aiUsage: AIUsageElongatedWidget(aiUsage: model.aiUsage, settings: model.settings, onOpen: { model.showTab(.aiUsage) })
        }
    }
}

/// Opaque in the middle, fading to clear at the left and right edges.
private struct EdgeFade: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: width)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
        }
    }
}

/// A small circular button in the widgets' blue (play, start) or grey (secondary).
private struct RoundButton: View {
    let symbol: String
    var filled = false
    var size: CGFloat
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? NotchColor.blue : Color.white.opacity(isHovering ? 0.2 : 0.12)))
                .brightness(filled && isHovering ? 0.08 : 0)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel(Text(label))
    }
}

// MARK: Music

private struct MusicWidget: View {
    let service: NowPlayingService
    @State private var scrub: Double?
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        VStack(spacing: 8 * s) {
            HStack(spacing: 12 * s) {
                Button { service.openSourceApp() } label: {
                    ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: 62 * s, cornerRadius: 12 * s)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Open player"))
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(info?.title ?? "")
                        .font(.system(size: 13.5 * s, weight: .bold))
                        .foregroundStyle(.white)
                    Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                        .font(.system(size: 11 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                    HStack(spacing: 14 * s) {
                        GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: 15 * s, label: info?.isPlaying == true ? "Pause" : "Play") {
                            service.togglePlayPause()
                        }
                        GlyphButton(symbol: "forward.fill", size: 13 * s, label: "Next Track") { service.nextTrack() }
                    }
                    .padding(.top, 5 * s)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TimelineView(.animation(minimumInterval: 0.5, paused: info?.isPlaying != true)) { context in
                let duration = info?.duration
                let elapsed = scrub.flatMap { value in duration.map { $0 * value } } ?? info?.elapsed(at: context.date) ?? 0
                VStack(spacing: 2 * s) {
                    ScrubBar(progress: scrub ?? info?.progress(at: context.date) ?? 0, isEnabled: duration != nil, knob: true) { value, ended in
                        scrub = ended ? nil : value
                        if ended, let duration { service.seek(to: value * duration) }
                    }
                    HStack {
                        Text(TimeFormatting.clock(elapsed))
                        Spacer()
                        Text(duration.map { TimeFormatting.remaining(elapsed: elapsed, duration: $0) } ?? "--:--")
                    }
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.secondaryText)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: Mirror

/// A circle that turns into a live, mirrored camera view when clicked.
private struct MirrorWidget: View {
    let model: IslandModel
    @State private var isOn = false
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let diameter = 84 * s
        Button {
            switch model.camera.state {
            case .granted: withAnimation(.smooth(duration: 0.3)) { isOn.toggle() }
            case .notAsked: model.camera.request()
            case .denied: model.camera.openPrivacySettings()
            case .noCamera: break
            }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(isHovering ? 0.14 : 0.09))
                if isOn, model.camera.state == .granted {
                    CameraPreview()
                        .clipShape(Circle())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(spacing: 5 * s) {
                        Image(systemName: "web.camera")
                            .font(.system(size: 19 * s, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Mirror")
                            .font(.system(size: 10 * s, weight: .semibold))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .onAppear { model.camera.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(isOn ? "Turn off the camera" : "Check how you look")
        .accessibilityLabel(Text("Camera Mirror"))
    }
}

// MARK: Calendar

/// The month, a strip of days around today (today in blue, weekends in red), and the chosen
/// day's events with a Join button for video calls.
private struct CalendarWidget: View {
    let model: IslandModel
    @State private var selected: Date?
    @Environment(\.notchScale) private var s

    var body: some View {
        let calendar = model.calendar
        TimelineView(.everyMinute) { context in
            let day = selected ?? context.date
            HStack(alignment: .top, spacing: 12 * s) {
                Button { model.showTab(.calendar) } label: {
                    Text(day.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 22 * s, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                .buttonStyle(PressableButtonStyle())
                .help("Open the month")
                VStack(alignment: .leading, spacing: 8 * s) {
                    DayStrip(today: context.date, selected: day, events: calendar.events) { picked in
                        withAnimation(.snappy(duration: 0.25)) {
                            selected = Calendar.current.isDate(picked, inSameDayAs: context.date) ? nil : picked
                        }
                    }
                    switch calendar.access {
                    case .granted:
                        DayEvents(events: CalendarRules.events(on: day, in: calendar.events, at: context.date), now: context.date) { event in
                            calendar.open(event)
                            model.collapse()
                        }
                    case .notAsked:
                        Button("Connect Calendar") { calendar.requestAccess() }
                            .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
                    case .denied, .limited:
                        Button("Allow Access") { calendar.openPrivacySettings() }
                            .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 4 * s)
        }
    }
}

/// The days of the month on a wheel, like Apple's pickers: the day in the middle is the chosen
/// one, largest and in blue, and the days either side shrink and fade the further out they are,
/// continuously as you scroll. Scroll, or click a day, to bring it to the middle.
private struct DayStrip: View {
    let today: Date
    let selected: Date
    let events: [CalendarEvent]
    let pick: (Date) -> Void
    @State private var centered: Date?
    @Environment(\.notchScale) private var s

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let days = CalendarRules.browsableDays(at: today)
        // Worked out once, not once per day in the strip.
        let busyDays = Set(events.map { calendar.startOfDay(for: $0.start) })
        let cell = 34 * s
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        let isSelected = calendar.isDate(day, inSameDayAs: selected)
                        Button {
                            withAnimation(.smooth(duration: 0.4)) { centered = day }
                        } label: {
                            DayFace(
                                day: day,
                                isSelected: isSelected,
                                isToday: calendar.isDate(day, inSameDayAs: today),
                                isPast: day < start,
                                hasEvents: busyDays.contains(day)
                            )
                            .frame(width: cell, height: 48 * s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .visualEffect { content, proxy in
                            // 0 in the middle of the strip, 1 three days out and beyond.
                            let distance = proxy.frame(in: .scrollView(axis: .horizontal)).midX
                                - (proxy.bounds(of: .scrollView(axis: .horizontal))?.midX ?? 0)
                            let t = min(abs(distance) / (cell * 3), 1)
                            return content
                                .scaleEffect(1.3 - 0.55 * t)
                                .opacity(1 - 0.7 * t)
                        }
                        .id(day)
                        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            // Room either side, so the first and last days can reach the middle too.
            .contentMargins(.horizontal, max(0, (geometry.size.width - cell) / 2), for: .scrollContent)
            .mask(EdgeFade(width: 22 * s))
        }
        .frame(height: 48 * s)
        .onAppear { centered = calendar.startOfDay(for: selected) }
        .onChange(of: centered) { _, day in
            if let day, !calendar.isDate(day, inSameDayAs: selected) { pick(day) }
        }
        .onChange(of: selected) { _, day in
            let day = calendar.startOfDay(for: day)
            if centered.map({ !calendar.isDate($0, inSameDayAs: day) }) ?? true {
                withAnimation(.smooth(duration: 0.4)) { centered = day }
            }
        }
    }
}

/// One day on the strip, drawn the same at every size: the wheel does the scaling.
private struct DayFace: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isPast: Bool
    let hasEvents: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let weekend = Calendar.current.isDateInWeekend(day)
        VStack(spacing: 1 * s) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 8 * s, weight: .bold))
                .foregroundStyle(isSelected ? NotchColor.blue : NotchColor.secondaryText)
            Text(day.formatted(.dateTime.day(.twoDigits)))
                .font(.system(size: 15 * s, weight: isSelected ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? NotchColor.blue : (weekend ? NotchColor.red.opacity(0.75) : .white.opacity(isPast ? 0.4 : 0.9)))
            Circle()
                .fill(isToday && !isSelected ? NotchColor.blue : (hasEvents && !isSelected ? Color.white.opacity(0.45) : .clear))
                .frame(width: 3 * s, height: 3 * s)
        }
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}

private struct DayEvents: View {
    let events: [CalendarEvent]
    let now: Date
    let open: (CalendarEvent) -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        if events.isEmpty {
            HStack(spacing: 6 * s) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 11 * s))
                Text("No events for this day")
                    .font(.system(size: 11 * s, weight: .medium))
            }
            .foregroundStyle(NotchColor.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 4 * s)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5 * s) {
                    ForEach(events) { event in
                        HStack(spacing: 7 * s) {
                            RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous)
                                .fill(NotchColor.accent(event.color))
                                .frame(width: 3 * s, height: 22 * s)
                            Button { open(event) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(event.title)
                                        .font(.system(size: 11.5 * s, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(CalendarRules.timeRange(for: event, at: now))
                                        .font(.system(size: 9.5 * s, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(event.isHappening(at: now) ? NotchColor.green : NotchColor.secondaryText)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableButtonStyle())
                            if let url = event.joinURL {
                                Button("Join") { NSWorkspace.shared.open(url) }
                                    .buttonStyle(JoinButtonStyle(scale: s))
                                    .help("Join on \(event.joinProvider?.rawValue ?? "the call")")
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct JoinButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5 * scale, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10 * scale)
            .frame(height: 22 * scale)
            .background(Capsule().fill(NotchColor.blue.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}

// MARK: Notes

private struct NotesWidget: View {
    let model: IslandModel
    @State private var controller = RichTextController()
    @Environment(\.notchScale) private var s

    var body: some View {
        NoteCard(model: model, controller: controller, fontSize: 12 * s)
            .padding(.vertical, 2 * s)
    }
}

// MARK: Timer

/// Hours, minutes and seconds on wheels, quick 1m and 5m, and a blue start button. While a
/// timer runs it shows the countdown instead.
private struct TimerWidget: View {
    let model: IslandModel
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @Environment(\.notchScale) private var s

    var body: some View {
        if let timer = model.timer.timer, model.timer.isActive {
            HStack(spacing: 12 * s) {
                Button { model.expand(.activity(.timer)) } label: {
                    CountdownText(timer: timer)
                        .font(.system(size: 34 * s, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(timer.isPaused ? NotchColor.secondaryText : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                RoundButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", filled: true, size: 34 * s, label: timer.isPaused ? "Resume" : "Pause") {
                    model.timer.togglePause()
                }
                RoundButton(symbol: "xmark", size: 34 * s, label: "Cancel") { model.cancelTimer() }
            }
            .frame(maxHeight: .infinity)
        } else {
            HStack(spacing: 10 * s) {
                RoundButton(symbol: "xmark", size: 20 * s, label: "Clear") {
                    withAnimation(.snappy) { hours = 0; minutes = 0; seconds = 0 }
                }
                HStack(spacing: 2 * s) {
                    Wheel(value: $hours, range: 0..<24, unit: "h")
                    Text(":").foregroundStyle(NotchColor.secondaryText)
                    Wheel(value: $minutes, range: 0..<60, unit: "m")
                    Text(":").foregroundStyle(NotchColor.secondaryText)
                    Wheel(value: $seconds, range: 0..<60, unit: "s")
                }
                .font(.system(size: 13 * s, weight: .semibold))
                VStack(spacing: 6 * s) {
                    QuickTime(label: "1m") { set(60) }
                    QuickTime(label: "5m") { set(300) }
                }
                RoundButton(symbol: "play.fill", filled: true, size: 34 * s, label: "Start") {
                    let total = TimeInterval(hours * 3600 + minutes * 60 + seconds)
                    model.startTimer(total > 0 ? total : 300)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func set(_ total: Int) {
        withAnimation(.snappy) {
            hours = total / 3600
            minutes = total % 3600 / 60
            seconds = total % 60
        }
    }
}

private struct QuickTime: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5 * s, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26 * s, height: 26 * s)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.2 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text("Set \(label)"))
    }
}

/// One column of a time picker: scroll or drag to change it, the chosen value in the middle.
private struct Wheel: View {
    @Binding var value: Int
    let range: Range<Int>
    let unit: String
    @State private var position: Int?
    @Environment(\.notchScale) private var s

    var body: some View {
        let row = 22 * s
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(range, id: \.self) { number in
                    HStack(alignment: .firstTextBaseline, spacing: 1 * s) {
                        Text(String(format: "%02d", number))
                            .monospacedDigit()
                        Text(unit)
                            .font(.system(size: 8 * s, weight: .semibold))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                    .foregroundStyle(.white)
                    .frame(height: row)
                    // Like the Clock app's picker: rows grow, brighten and face you as they near
                    // the middle, and tilt away above and below it, continuously as it turns.
                    .visualEffect { content, proxy in
                        let distance = proxy.frame(in: .scrollView(axis: .vertical)).midY
                            - (proxy.bounds(of: .scrollView(axis: .vertical))?.midY ?? 0)
                        let t = max(-1, min(distance / (row * 1.5), 1))
                        return content
                            .scaleEffect(1.12 - 0.3 * abs(t))
                            .opacity(1 - 0.75 * abs(t))
                            .rotation3DEffect(.degrees(-38 * t), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    }
                    .id(number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, row, for: .scrollContent)
        .frame(width: 38 * s, height: row * 3)
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .onAppear { position = value }
        .onChange(of: position) { _, new in
            if let new, new != value { value = new }
        }
        .onChange(of: value) { _, new in
            if position != new { withAnimation(.smooth(duration: 0.4)) { position = new } }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(value) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound - 1)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

// MARK: To-dos

private struct TodosWidget: View {
    let model: IslandModel
    @State private var draft = ""
    @FocusState private var isTyping: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let todos = model.todos
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(spacing: 6 * s) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(isTyping ? NotchColor.blue : NotchColor.secondaryText)
                TextField("New task…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isTyping)
                    .onSubmit {
                        withAnimation(.snappy(duration: 0.3)) { todos.add(draft) }
                        draft = ""
                    }
                    .onKeyPress(.escape) {
                        model.collapse()
                        return .handled
                    }
            }
            .padding(.horizontal, 9 * s)
            .frame(height: 26 * s)
            .background(Capsule().fill(Color.white.opacity(isTyping ? 0.12 : 0.07)))
            .onChange(of: isTyping) { _, typing in model.isTypingInNook = typing }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3 * s) {
                    ForEach(todos.ordered) { item in
                        TodoRow(item: item) {
                            withAnimation(.snappy(duration: 0.3)) { todos.toggle(item.id) }
                            Haptics.perform(enabled: model.settings.hapticsEnabled)
                        } remove: {
                            withAnimation(.snappy(duration: 0.3)) { todos.remove(item.id) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4 * s)
    }
}

private struct TodoRow: View {
    let item: TodoStore.Item
    let toggle: () -> Void
    let remove: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 7 * s) {
            Button(action: toggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13 * s))
                    .foregroundStyle(item.isDone ? NotchColor.blue : NotchColor.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text(item.isDone ? "Mark \(item.title) as not done" : "Complete \(item.title)"))
            Text(item.title)
                .font(.system(size: 11.5 * s, weight: .medium))
                .strikethrough(item.isDone, color: NotchColor.secondaryText)
                .foregroundStyle(item.isDone ? NotchColor.secondaryText : .white)
                .lineLimit(1)
            Spacer(minLength: 4 * s)
            if isHovering {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8 * s, weight: .bold))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Delete \(item.title)"))
            }
        }
        .frame(height: 20 * s)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
