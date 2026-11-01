import SwiftUI

// MARK: - Panel Body (Nook View)

public struct AIUsagePanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s
    @State private var now = Date()

    public init(model: IslandModel) {
        self.model = model
    }

    public var body: some View {
        let ai = model.aiUsage
        let visible = ai.visibleUsages(selected: model.settings.selectedAIProviders)
        VStack(spacing: 8 * s) {
            // Header bar: last refresh info and manual refresh button
            HStack {
                if let last = ai.lastRefreshAttempt {
                    HStack(spacing: 4 * s) {
                        Circle()
                            .fill(!visible.isEmpty ? NotchColor.green : NotchColor.yellow)
                            .frame(width: 6 * s, height: 6 * s)
                        Text("Checked \(lastUpdatedText(last))")
                            .font(.system(size: 11 * s))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                } else {
                    Text("AI Agent Usage & Rate Limits")
                        .font(.system(size: 11 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }

                Spacer()

                Button {
                    ai.refreshAll(userInitiated: true)
                } label: {
                    HStack(spacing: 4 * s) {
                        if ai.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10 * s, weight: .medium))
                        }
                        Text(ai.isRefreshing ? "Refreshing…" : "Refresh")
                            .font(.system(size: 11 * s, weight: .medium))
                    }
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 3 * s)
                    .background(NotchColor.buttonFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(ai.isRefreshing)
            }
            .padding(.horizontal, 4 * s)

            // Content: Provider cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10 * s) {
                    if visible.isEmpty {
                        emptyStateView(ai.isRefreshing ? "Checking connected providers…" : "No connected AI providers to show.")
                    } else {
                        ForEach(visible) { usage in
                            providerCard(for: usage)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2 * s)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if visible.isEmpty && !ai.isRefreshing && !model.settings.selectedAIProviders.isEmpty {
                ai.refreshAll(userInitiated: false)
            }
        }
        .task {
            // Periodic timer to keep countdown strings fresh
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
    }

    private func lastUpdatedText(_ date: Date) -> String {
        let diff = Int(now.timeIntervalSince(date))
        if diff < 10 { return "just now" }
        if diff < 60 { return "\(diff)s ago" }
        let minutes = diff / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    @ViewBuilder
    private func providerCard(for usage: AIProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            // Title row
            HStack(spacing: 8 * s) {
                Image(systemName: usage.provider.symbolName)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(usage.provider.brandColor)
                    .frame(width: 20 * s, height: 20 * s)
                    .background(usage.provider.brandColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5 * s))

                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.provider.displayName)
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(.white)

                    if let plan = usage.plan {
                        Text(plan)
                            .font(.system(size: 10 * s))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                }

                Spacer()

                statusBadge(for: usage.status)
            }

            HStack(alignment: .top) {
                Text("Models")
                    .font(.system(size: 11 * s, weight: .medium))
                Spacer()
                Text(usage.model ?? (usage.windows.isEmpty ? "Not reported" : "Shared quota — not per-model usage"))
                    .font(.system(size: 11 * s))
                    .foregroundStyle(NotchColor.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            // Quota / Rate Limit Windows
            if !usage.windows.isEmpty {
                VStack(spacing: 6 * s) {
                    ForEach(usage.windows) { window in
                        quotaWindowRow(window)
                    }
                }
            } else if case .active = usage.status {
                HStack {
                    Text("Rate limits / Quota:")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                    Spacer()
                    Text("Not available from provider")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }

            // Token Breakdown
            if let tokens = usage.tokens {
                tokenBreakdownView(tokens)
            }

            // Cost or details footer
            HStack {
                if let cost = usage.costEstimate {
                    Text("Today's cost: \(cost)")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundStyle(NotchColor.green)
                }

                Spacer()

                Text(usage.attribution)
                    .font(.system(size: 9 * s))
                    .foregroundStyle(NotchColor.secondaryText.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(10 * s)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10 * s))
        .overlay(
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func quotaWindowRow(_ window: AIUsageWindow) -> some View {
        VStack(spacing: 3 * s) {
            HStack {
                HStack(spacing: 4 * s) {
                    Text(window.name)
                        .font(.system(size: 11 * s, weight: .medium))
                        .foregroundStyle(.white)
                    if window.isEstimated {
                        Text("est.")
                            .font(.system(size: 9 * s))
                            .foregroundStyle(NotchColor.yellow)
                            .padding(.horizontal, 3 * s)
                            .background(NotchColor.yellow.opacity(0.15), in: Capsule())
                    }
                }

                Spacer()

                if let remaining = window.remainingPercent {
                    Text("\(Int(remaining.rounded()))% left")
                        .font(.system(size: 11 * s, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(quotaTint(forRemaining: remaining))
                } else if let count = window.usedCount, let limit = window.limitCount {
                    Text("\(count) / \(limit)")
                        .font(.system(size: 11 * s))
                        .monospacedDigit()
                        .foregroundStyle(NotchColor.secondaryText)
                } else {
                    Text("Not available")
                        .font(.system(size: 10 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }

            // Progress bar
            if let remaining = window.remainingPercent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(quotaTint(forRemaining: remaining))
                            .frame(width: geo.size.width * CGFloat(remaining / 100.0))
                    }
                }
                .frame(height: 4 * s)
            }

            // Reset time and countdown
            if let resetText = window.countdownString(from: now) {
                HStack {
                    if let localTime = window.localResetTimeString() {
                        Text("Resets \(localTime)")
                            .font(.system(size: 9 * s))
                            .foregroundStyle(NotchColor.secondaryText)
                    }
                    Spacer()
                    Text(resetText)
                        .font(.system(size: 9 * s, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
        }
        .padding(.vertical, 2 * s)
    }

    @ViewBuilder
    private func tokenBreakdownView(_ tokens: AITokenBreakdown) -> some View {
        HStack(spacing: 8 * s) {
            tokenMetric("Input", count: tokens.promptTokens)
            tokenMetric("Output", count: tokens.completionTokens)
            if tokens.cacheReadTokens != nil || tokens.cacheWriteTokens != nil {
                tokenMetric("Cached", count: (tokens.cacheReadTokens ?? 0) + (tokens.cacheWriteTokens ?? 0))
            }
            Spacer()
            if let total = tokens.totalTokens {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Total")
                        .font(.system(size: 9 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                    Text(AITokenBreakdown.formatCount(total))
                        .font(.system(size: 10 * s, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.top, 2 * s)
    }

    private func tokenMetric(_ label: String, count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9 * s))
                .foregroundStyle(NotchColor.secondaryText)
            Text(count.map { AITokenBreakdown.formatCount($0) } ?? "–")
                .font(.system(size: 10 * s, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: AIProviderStatus) -> some View {
        switch status {
        case .active:
            Text("Active")
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundStyle(NotchColor.green)
                .padding(.horizontal, 6 * s)
                .padding(.vertical, 2 * s)
                .background(NotchColor.green.opacity(0.12), in: Capsule())
        case .loading:
            HStack(spacing: 3 * s) {
                ProgressView().controlSize(.small).scaleEffect(0.6)
                Text("Checking…")
                    .font(.system(size: 9 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        case .unconfigured:
            Button {
                model.openSettings(.codingAssistants)
            } label: {
                Text("Set up")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundStyle(NotchColor.blue)
                    .padding(.horizontal, 6 * s)
                    .padding(.vertical, 2 * s)
                    .background(NotchColor.blue.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        case .signedOut(let msg):
            Text("Sign in: \(msg)")
                .font(.system(size: 9 * s))
                .foregroundStyle(NotchColor.orange)
                .lineLimit(1)
        case .offline(let msg):
            Text("Offline: \(msg)")
                .font(.system(size: 9 * s))
                .foregroundStyle(NotchColor.secondaryText)
                .lineLimit(1)
        case .error(let msg), .unavailable(let msg):
            Text(msg)
                .font(.system(size: 9 * s))
                .foregroundStyle(NotchColor.red)
                .lineLimit(1)
        }
    }

    private func quotaTint(forRemaining remaining: Double) -> Color {
        if remaining > 40 { return NotchColor.green }
        if remaining > 15 { return NotchColor.yellow }
        return NotchColor.red
    }

    private func emptyStateView(_ message: String) -> some View {
        VStack(spacing: 8 * s) {
            Image(systemName: "sparkles")
                .font(.system(size: 24 * s))
                .foregroundStyle(NotchColor.secondaryText)
            Text(message)
                .font(.system(size: 12 * s))
                .foregroundStyle(NotchColor.secondaryText)
                .multilineTextAlignment(.center)
            if !model.aiUsage.isRefreshing {
                if model.settings.aiUsageCodexEnabled && !model.settings.aiUsageCodexUseLocalCLI {
                    Button("Connect signed-in Codex") {
                        model.settings.aiUsageCodexUseLocalCLI = true
                        model.aiUsage.refreshAll(userInitiated: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                ForEach(AIProvider.allCases.filter { model.settings.selectedAIProviders.contains($0) }, id: \.self) { provider in
                    if let usage = model.aiUsage.usages[provider], !usage.status.isSuccess {
                        Text("\(provider.displayName): \(usage.status.statusDescription)")
                            .font(.system(size: 10 * s))
                            .foregroundStyle(NotchColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("Configure in Settings") {
                model.openSettings(.codingAssistants)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20 * s)
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
