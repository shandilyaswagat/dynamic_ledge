import SwiftUI

// Styled after Apple's Calendar widgets: a small month on the left with the month name in red,
// "Up Next" on the right with each event's calendar colour as a slim bar.

/// This month on the left, what's coming up on the right. Click a date to see that day's events,
/// and an event to open it in Calendar.
struct CalendarPanelBody: View {
    let model: IslandModel
    /// The day picked in the month grid; nil shows what's coming up.
    @State private var selected: Date?
    @Environment(\.notchScale) private var s

    var body: some View {
        let calendar = model.calendar
        switch calendar.access {
        case .notAsked:
            ConnectPrompt(text: "See your month and what's coming up.", button: "Connect Calendar", tint: NotchColor.red) {
                calendar.requestAccess()
            }
        case .denied:
            ConnectPrompt(text: "Calendar access is off for Dynamic Notch.", button: "Turn On in Settings", tint: .white) {
                calendar.openPrivacySettings()
            }
        case .limited:
            ConnectPrompt(text: "Dynamic Notch can add events but can't see them yet.", button: "Allow Full Access", tint: .white) {
                calendar.openPrivacySettings()
            }
        case .granted:
            TimelineView(.everyMinute) { context in
                HStack(alignment: .top, spacing: 0) {
                    MonthGrid(today: context.date, selected: selected, busyDays: busyDays(calendar.events)) { day in
                        withAnimation(.snappy(duration: 0.25)) {
                            // Today, or the day already picked, goes back to what's coming up.
                            let cal = Calendar.current
                            let isCurrent = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
                            selected = isCurrent || cal.isDate(day, inSameDayAs: context.date) ? nil : day
                        }
                    }
                    .frame(width: 168 * s, alignment: .leading)
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .padding(.horizontal, 16 * s)
                        .padding(.vertical, 2 * s)
                    Group {
                        if let selected {
                            DayList(model: model, day: selected, now: context.date)
                        } else {
                            UpNext(model: model, now: context.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.top, 2 * s)
        }
    }

    private func busyDays(_ events: [CalendarEvent]) -> Set<Int> {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: Date()) else { return [] }
        return Set(events.compactMap { event in
            month.contains(event.start) ? calendar.component(.day, from: event.start) : nil
        })
    }
}

/// The events on the day picked in the month grid.
private struct DayList: View {
    let model: IslandModel
    let day: Date
    let now: Date
    @Environment(\.notchScale) private var s

    var body: some View {
        let events = CalendarRules.events(on: day, in: model.calendar.events, at: now)
        let shown = events.prefix(3)
        VStack(alignment: .leading, spacing: 6 * s) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())
                .font(.system(size: 9.5 * s, weight: .semibold))
                .kerning(0.4 * s)
                .foregroundStyle(NotchColor.secondaryText)
            if events.isEmpty {
                HStack(spacing: 8 * s) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16 * s))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(NotchColor.secondaryText)
                    Text("No events")
                        .font(.system(size: 12 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .padding(.top, 8 * s)
            } else {
                ForEach(shown) { event in
                    EventRow(event: event, now: now) { model.calendar.open(event); model.collapse() }
                }
                if events.count > shown.count {
                    Text("+\(events.count - shown.count) more")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
        }
        .id(day)
        .transition(.opacity)
    }
}

/// The next few events, labelled with their day when it isn't today.
private struct UpNext: View {
    let model: IslandModel
    let now: Date
    @Environment(\.notchScale) private var s

    var body: some View {
        let upcoming = CalendarRules.upcoming(in: model.calendar.events, at: now, limit: 3)
        VStack(alignment: .leading, spacing: 6 * s) {
            Text(upcoming.first.map { CalendarRules.dayLabel(for: $0, at: now) }?.uppercased() ?? String(localized: "UP NEXT"))
                .font(.system(size: 9.5 * s, weight: .semibold))
                .kerning(0.4 * s)
                .foregroundStyle(NotchColor.secondaryText)
            if upcoming.isEmpty {
                HStack(spacing: 8 * s) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 16 * s))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(NotchColor.secondaryText)
                    Text("Nothing on your calendar this week")
                        .font(.system(size: 12 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .padding(.top, 8 * s)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                    // A new day starts a new little heading.
                    if index > 0, CalendarRules.dayLabel(for: event, at: now) != CalendarRules.dayLabel(for: upcoming[index - 1], at: now) {
                        Text(CalendarRules.dayLabel(for: event, at: now).uppercased())
                            .font(.system(size: 9.5 * s, weight: .semibold))
                            .kerning(0.4 * s)
                            .foregroundStyle(NotchColor.secondaryText)
                            .padding(.top, 1 * s)
                    }
                    EventRow(event: event, now: now) { model.calendar.open(event); model.collapse() }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let open: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let happening = event.isHappening(at: now)
        Button(action: open) {
            HStack(spacing: 9 * s) {
                RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous)
                    .fill(NotchColor.accent(event.color))
                    .frame(width: 3 * s, height: 26 * s)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(event.title)
                        .font(.system(size: 12.5 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(CalendarRules.timeRange(for: event, at: now))
                        .font(.system(size: 10.5 * s, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(happening ? NotchColor.accent(event.color) : NotchColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s)
            .padding(.vertical, 2 * s)
            .background(
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.08 : 0))
            )
            .padding(.horizontal, -6 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .help("Open in Calendar")
        .accessibilityLabel(Text("\(event.title), \(CalendarRules.timeRange(for: event, at: now))"))
    }
}

/// A small month, today in a red circle, a dot under days that have events. Click a day to pick it.
private struct MonthGrid: View {
    let today: Date
    let selected: Date?
    let busyDays: Set<Int>
    let pick: (Date) -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        let month = MonthLayout(containing: today)
        let columns = Array(repeating: GridItem(.fixed(22 * s), spacing: 1 * s), count: 7)
        VStack(alignment: .leading, spacing: 4 * s) {
            Text(today.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 10 * s, weight: .bold))
                .kerning(0.5 * s)
                .foregroundStyle(NotchColor.red)
            LazyVGrid(columns: columns, spacing: 0) {
                // Weekday headers and day cells need distinct ids inside one grid.
                ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(height: 12 * s)
                }
                ForEach(month.cells.indices.map { $0 + 100 }, id: \.self) { index in
                    let day = month.cells[index - 100]
                    let date: Date? = day.flatMap(dayDate)
                    DayCell(day: day, date: date, isToday: day == month.today, isSelected: isSelected(date),
                            isBusy: day.map(busyDays.contains) ?? false, pick: pick)
                }
            }
        }
    }

    private func isSelected(_ date: Date?) -> Bool {
        guard let date, let selected else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selected)
    }

    private func dayDate(_ day: Int) -> Date? {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month], from: today)
        parts.day = day
        return calendar.date(from: parts)
    }
}

private struct DayCell: View {
    let day: Int?
    let date: Date?
    let isToday: Bool
    let isSelected: Bool
    let isBusy: Bool
    let pick: (Date) -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        if let date {
            Button { pick(date) } label: { face }
                .buttonStyle(PressableButtonStyle())
                .onHover { isHovering = $0 }
                .accessibilityLabel(Text(date.formatted(date: .complete, time: .omitted)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
        }
    }

    private var face: some View {
        ZStack {
            if isToday {
                Circle().fill(NotchColor.red).frame(width: 15 * s, height: 15 * s)
            } else if isSelected {
                Circle().fill(Color.white.opacity(0.22)).frame(width: 15 * s, height: 15 * s)
            } else if isHovering {
                Circle().fill(Color.white.opacity(0.1)).frame(width: 15 * s, height: 15 * s)
            }
            Text(day.map(String.init) ?? "")
                .font(.system(size: 9 * s, weight: isToday || isSelected ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isToday || isSelected ? 1 : 0.85))
            if isBusy, !isToday, !isSelected {
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2.5 * s, height: 2.5 * s)
                    .offset(y: 7 * s)
            }
        }
        .frame(width: 22 * s, height: 14.5 * s)
        .contentShape(Rectangle())
    }
}
