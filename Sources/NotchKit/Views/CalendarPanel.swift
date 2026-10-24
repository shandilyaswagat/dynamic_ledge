import SwiftUI

// Styled after Apple's Calendar widgets: a small month on the left with the month name in red,
// "Up Next" on the right with each event's calendar colour as a slim bar.

/// This month on the left, what's coming up on the right. Click an event to open it in Calendar.
struct CalendarPanelBody: View {
    let model: IslandModel
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
                    MonthGrid(today: context.date, busyDays: busyDays(calendar.events))
                        .frame(width: 168 * s, alignment: .leading)
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .padding(.horizontal, 16 * s)
                        .padding(.vertical, 2 * s)
                    UpNext(model: model, now: context.date)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.top, 2 * s)
        }
    }

    private func busyDays(_ events: [CalendarEvent]) -> Set<Int> {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        return Set(events.compactMap { event in
            calendar.component(.month, from: event.start) == month ? calendar.component(.day, from: event.start) : nil
        })
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

/// A small month, today in a red circle, a dot under days that have events.
private struct MonthGrid: View {
    let today: Date
    let busyDays: Set<Int>
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
                    DayCell(day: day, isToday: day == month.today, isBusy: day.map(busyDays.contains) ?? false)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(today.formatted(date: .complete, time: .omitted)))
    }
}

private struct DayCell: View {
    let day: Int?
    let isToday: Bool
    let isBusy: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        ZStack {
            if isToday {
                Circle().fill(NotchColor.red).frame(width: 15 * s, height: 15 * s)
            }
            Text(day.map(String.init) ?? "")
                .font(.system(size: 9 * s, weight: isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isToday ? 1 : 0.85))
            if isBusy, !isToday {
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2.5 * s, height: 2.5 * s)
                    .offset(y: 7 * s)
            }
        }
        .frame(height: 14.5 * s)
    }
}
