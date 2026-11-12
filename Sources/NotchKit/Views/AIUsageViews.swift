import SwiftUI
import Charts

public struct AIUsagePanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s
    @State private var page = "Usage"

    public init(model: IslandModel) { self.model = model }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 8 * s) {
                HStack {
                    Picker("Usage view", selection: $page) {
                        Text("Usage").tag("Usage")
                        Text("History").tag("History")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170 * s)
                    Spacer()
                    Button {
                        model.aiUsage.refreshAll(userInitiated: true)
                    } label: {
                        Label(model.aiUsage.isRefreshing ? "Checking…" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11 * s))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.aiUsage.isRefreshing)
                }
                ScrollView {
                    if page == "Usage" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190 * s), alignment: .top)], alignment: .leading, spacing: 8 * s) {
                            ForEach(AIProvider.allCases.filter { model.settings.selectedAIProviders.contains($0) }) { provider in
                                providerCard(model.aiUsage.usages[provider] ?? .unconfigured(for: provider), now: context.date)
                            }
                        }
                        if model.settings.selectedAIProviders.isEmpty {
                            message("Choose an assistant in Settings to see its usage.")
                        }
                    } else {
                        history(now: context.date)
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { model.aiUsage.refreshIfOutdated() }
    }

    private func providerCard(_ usage: AIProviderUsage, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack {
                Image(systemName: usage.provider.symbolName).foregroundStyle(usage.provider.brandColor)
                Text(usage.provider.shortName).fontWeight(.semibold)
                Spacer(minLength: 0)
                if usage.isStale(relativeTo: now), usage.lastUpdated != nil {
                    Text("Stale").foregroundStyle(NotchColor.yellow)
                }
            }
            .font(.system(size: 12 * s))
            if usage.status.isSuccess {
                ForEach(usage.windows) { window in
                    VStack(alignment: .leading, spacing: 3 * s) {
                        HStack {
                            Text(window.name).lineLimit(1)
                            Spacer(minLength: 3)
                            Text(window.remainingPercent.map { "\(Int($0.rounded()))% left" } ?? "Not reported")
                                .foregroundStyle(tint(window.remainingPercent))
                                .monospacedDigit()
                        }
                        .font(.system(size: 10 * s))
                        if let remaining = window.remainingPercent {
                            ProgressView(value: remaining, total: 100).tint(tint(remaining))
                                .accessibilityLabel("\(window.name): \(Int(remaining)) percent allowance remaining")
                        }
                        if let reset = window.countdownString(from: now) {
                            Text(reset).font(.system(size: 9 * s)).foregroundStyle(NotchColor.secondaryText)
                        }
                    }
                }
                if usage.windows.isEmpty { message("Allowance not reported") }
                Divider().overlay(Color.white.opacity(0.12))
                if usage.provider == .codex {
                    let today = model.aiUsage.tokenHistory.days.first { Calendar.current.isDate($0.day, inSameDayAs: now) }
                    metric("Tokens today · local", value: today.map { AITokenBreakdown.formatCount($0.total) } ?? "Not reported")
                    metric("Estimated cost · USD", value: today.flatMap { model.aiUsage.costRates.estimate($0) }.map { String(format: "$%.2f", $0) } ?? "Not configured")
                    Text(model.aiUsage.recordsHistory ? "Custom rates · not your bill" : "Enable history for local tokens")
                        .font(.system(size: 9 * s)).foregroundStyle(NotchColor.secondaryText)
                } else {
                    metric("Tokens · latest local session", value: usage.tokens?.totalTokens.map(AITokenBreakdown.formatCount) ?? "Not reported")
                    metric("Estimated cost", value: usage.costEstimate ?? "Not reported")
                }
                if let date = usage.lastUpdated {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.system(size: 9 * s)).foregroundStyle(NotchColor.secondaryText)
                }
            } else {
                Text(usage.status.statusDescription)
                    .font(.system(size: 11 * s)).foregroundStyle(NotchColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10 * s)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10 * s))
        .overlay(RoundedRectangle(cornerRadius: 10 * s).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    @ViewBuilder
    private func history(now: Date) -> some View {
        if !model.aiUsage.recordsHistory {
            VStack(spacing: 10 * s) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 24 * s))
                message("History is off. Enable it in Settings to keep allowance readings and read local Codex token counts.")
                Button("Usage settings") { model.openSettings(.codingAssistants) }
                    .buttonStyle(.bordered)
            }
            .padding(12 * s)
        } else {
            VStack(alignment: .leading, spacing: 10 * s) {
                if model.settings.selectedAIProviders.contains(.codex) {
                    tokenHistory
                }
                let samples = model.aiUsage.quotaHistory.filter {
                    model.settings.selectedAIProviders.contains($0.provider) && $0.date >= now.addingTimeInterval(-7 * 86400)
                }
                Text("Allowance left · recorded samples").font(.system(size: 12 * s, weight: .semibold))
                if samples.isEmpty {
                    message("No readings yet. Refresh a connected assistant to start recording.")
                } else {
                    Chart(samples) { sample in
                        PointMark(x: .value("Time", sample.date), y: .value("Left", sample.remaining))
                            .foregroundStyle(by: .value("Assistant", sample.provider.shortName))
                            .symbolSize(12)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 90 * s)
                    .accessibilityLabel("Recorded lowest allowance remaining for each assistant, from zero to one hundred percent")
                    message("Lowest allowance per assistant at each check. Gaps mean no readings; resets can raise the percentage.")
                }
            }
            .padding(4 * s)
        }
    }

    private var tokenHistory: some View {
        let history = model.aiUsage.tokenHistory
        return VStack(alignment: .leading, spacing: 8 * s) {
            Text("Codex tokens · last 7 days · local")
                .font(.system(size: 12 * s, weight: .semibold))
            if history.days.isEmpty {
                message("No local token events found. Run a Codex task, then refresh. Cloud sessions are not included.")
            } else {
                Chart(history.days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Tokens", day.total))
                        .foregroundStyle(AIProvider.codex.brandColor)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 85 * s)
                ForEach(history.days.reversed()) { day in
                    HStack {
                        Text(day.day, format: .dateTime.month(.abbreviated).day())
                        Spacer()
                        Text("\(AITokenBreakdown.formatCount(day.total)) tokens")
                        Text(model.aiUsage.costRates.estimate(day).map { String(format: "~$%.2f", $0) } ?? "Cost —")
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                    .font(.system(size: 10 * s)).monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
                message("Costs use your blended USD rates, not subscription billing. Cached input is counted once. Missing days have no recorded events.")
            }
            if history.isPartial {
                Text("Partial history: some files or token events could not be read within the scan limits.")
                    .font(.system(size: 10 * s)).foregroundStyle(NotchColor.yellow)
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(NotchColor.secondaryText)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 10 * s))
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 10 * s)).foregroundStyle(NotchColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tint(_ remaining: Double?) -> Color {
        guard let remaining else { return NotchColor.secondaryText }
        return remaining > 40 ? NotchColor.green : remaining > 15 ? NotchColor.yellow : NotchColor.red
    }
}

// MARK: - Home Widget

public struct AIUsageHomeWidget: View {
    let aiUsage: AIUsageService
    let settings: SettingsStore
    let onOpen: () -> Void
    @Environment(\.notchScale) private var s

    public init(aiUsage: AIUsageService, settings: SettingsStore, onOpen: @escaping () -> Void) {
        self.aiUsage = aiUsage
        self.settings = settings
        self.onOpen = onOpen
    }

    public var body: some View {
        let visible = aiUsage.visibleUsages(selected: settings.selectedAIProviders)
        let remaining = visible.flatMap(\.windows).compactMap(\.remainingPercent).min()
        let reset = visible.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > Date() }.min()
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4 * s) {
                HStack(spacing: 4 * s) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.orange)
                    Text("AI Quotas")
                        .font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if let rem = remaining {
                        Text("\(Int(rem.rounded()))% left")
                            .font(.system(size: 10 * s, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(rem > 25 ? NotchColor.green : NotchColor.yellow)
                    }
                }

                if let rem = remaining {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(rem > 25 ? NotchColor.green : NotchColor.yellow)
                                .frame(width: max(4, geo.size.width * CGFloat(rem / 100.0)))
                        }
                    }
                    .frame(height: 3 * s)
                }

                HStack(spacing: 6 * s) {
                    ForEach(visible) { usage in
                        HStack(spacing: 2 * s) {
                            Circle().fill(usage.provider.brandColor).frame(width: 4 * s, height: 4 * s)
                            Text(usage.provider.shortName)
                                .font(.system(size: 9 * s))
                                .foregroundStyle(NotchColor.secondaryText)
                        }
                    }
                    Spacer()
                    if let reset {
                        let mins = max(1, Int(reset.timeIntervalSinceNow / 60))
                        Text("resets in \(mins)m")
                            .font(.system(size: 9 * s))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                }
            }
            .padding(8 * s)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8 * s))
            .overlay(RoundedRectangle(cornerRadius: 8 * s).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Elongated Row Widget

public struct AIUsageElongatedWidget: View {
    let aiUsage: AIUsageService
    let settings: SettingsStore
    let onOpen: () -> Void
    @Environment(\.notchScale) private var s

    public init(aiUsage: AIUsageService, settings: SettingsStore, onOpen: @escaping () -> Void) {
        self.aiUsage = aiUsage
        self.settings = settings
        self.onOpen = onOpen
    }

    public var body: some View {
        let remaining = aiUsage.visibleUsages(selected: settings.selectedAIProviders).flatMap(\.windows).compactMap(\.remainingPercent).min()
        Button(action: onOpen) {
            HStack(spacing: 8 * s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(NotchColor.orange)

                VStack(alignment: .leading, spacing: 2 * s) {
                    HStack(spacing: 4 * s) {
                        Text("AI Quotas")
                            .font(.system(size: 11 * s, weight: .semibold))
                            .foregroundStyle(.white)
                        if let rem = remaining {
                            Text("\(Int(rem.rounded()))% left")
                                .font(.system(size: 10 * s, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(rem > 25 ? NotchColor.green : NotchColor.yellow)
                        }
                    }

                    if let rem = remaining {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(rem > 25 ? NotchColor.green : NotchColor.yellow)
                                    .frame(width: max(3, geo.size.width * CGFloat(rem / 100.0)))
                            }
                        }
                        .frame(width: 80 * s, height: 3 * s)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Value

/// The lowest limit left across the ticked assistants, beside the camera.
struct AIUsageCompactValue: View {
    /// 0…100, or nil before the first check.
    let remaining: Double?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
                if let remaining {
                    Circle().trim(from: 0, to: max(0, min(1, remaining / 100)))
                        .stroke(remaining > 25 ? NotchColor.green : NotchColor.yellow, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: fontSize * 0.8, height: fontSize * 0.8)
            .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 0) {
                Text("LEFT")
                    .font(.system(size: max(7, fontSize * 0.55), weight: .bold))
                    .kerning(0.3)
                    .foregroundStyle(NotchColor.secondaryText)
                Text(remaining.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.system(size: fontSize * 0.9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(remaining.map { $0 > 25 ? NotchColor.green : NotchColor.yellow } ?? NotchColor.secondaryText)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "Lowest allowance: \(Int($0)) percent left" } ?? "Allowance unavailable")
    }
}
