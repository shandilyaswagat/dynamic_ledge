import Foundation
import os

/// Reads the local Google Antigravity session and token metrics from `~/.gemini`, without transmitting credentials.
public enum AntigravityUsageReader {
    public static func read() async -> AIProviderUsage {
        if var quota = await AntigravityQuotaReader.read() {
            // The quota service doesn't name the model; the transcripts are read only for that.
            guard quota.model == nil else { return quota }
            let transcriptInfo = await Task.detached(priority: .utility) { scanTranscripts() }.value
            if let model = transcriptInfo.modelName {
                quota = AIProviderUsage(
                    provider: quota.provider,
                    status: quota.status,
                    accountName: quota.accountName,
                    plan: quota.plan,
                    model: model,
                    windows: quota.windows,
                    tokens: quota.tokens,
                    costEstimate: quota.costEstimate,
                    lastUpdated: quota.lastUpdated,
                    attribution: quota.attribution
                )
            }
            return quota
        }
        return await Task.detached(priority: .utility) { readSync() }.value
    }

    /// Intermediate result from scanning transcript files.
    private struct TranscriptInfo: Sendable {
        var observedModels: Set<String> = []
        var latestSessionInput: Int = 0
        var latestSessionOutput: Int = 0
        var latestSessionCache: Int = 0
        var todayInput: Int = 0
        var todayOutput: Int = 0
        var todayCache: Int = 0
        var hasTranscripts: Bool = false

        var modelName: String? {
            observedModels.isEmpty ? nil : observedModels.sorted().joined(separator: ", ")
        }
    }

    /// Scans recent Antigravity transcript logs for model names, token counts, and account info.
    private static func scanTranscripts() -> TranscriptInfo {
        var info = TranscriptInfo()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let brainDir = home
            .appendingPathComponent(".gemini")
            .appendingPathComponent("antigravity")
            .appendingPathComponent("brain")

        guard FileManager.default.fileExists(atPath: brainDir.path),
              let convDirs = try? FileManager.default.contentsOfDirectory(
                at: brainDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return info }

        let sortedDirs = convDirs.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA > dateB
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var isFirst = true

        for dir in sortedDirs.prefix(15) {
            let logsDir = dir
                .appendingPathComponent(".system_generated")
                .appendingPathComponent("logs")
            let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")
            guard let (stats, modDate) = scan(transcriptURL) else { continue }

            info.hasTranscripts = true
            info.observedModels.formUnion(stats.models)
            // The compact transcript can cut content short; the full one is larger, so it's only
            // read while no model has been found.
            if info.observedModels.isEmpty, let (full, _) = scan(logsDir.appendingPathComponent("transcript_full.jsonl")) {
                info.observedModels.formUnion(full.models)
            }

            if isFirst {
                info.latestSessionInput = stats.input
                info.latestSessionOutput = stats.output
                info.latestSessionCache = stats.cache
                isFirst = false
            }
            if modDate >= today {
                info.todayInput += stats.input
                info.todayOutput += stats.output
                info.todayCache += stats.cache
            }
        }

        return info
    }

    /// What one transcript file holds.
    private struct FileStats: Sendable {
        var models: Set<String> = []
        var input = 0
        var output = 0
        var cache = 0
    }

    /// Transcripts already read, by path, with the date and size they had. A file is only read
    /// again once it changes, so a refresh usually reads nothing.
    private static let cache = OSAllocatedUnfairLock(initialState: [String: (date: Date, size: Int, stats: FileStats)]())

    private static func scan(_ url: URL) -> (FileStats, Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let size = (attributes[.size] as? Int) ?? 0
        if let hit = cache.withLock({ $0[url.path] }), hit.date == date, hit.size == size {
            return (hit.stats, date)
        }
        guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else { return nil }
        var stats = FileStats()
        content.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let step = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            for key in ["model", "model_id", "modelId", "model_name"] {
                if let model = step[key] as? String, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stats.models.insert(model)
                }
            }
            if let stepContent = step["content"] as? String {
                extractModelsFromContent(stepContent, into: &stats.models)
            }
            stats.input += step["input_tokens"] as? Int ?? 0
            stats.output += step["output_tokens"] as? Int ?? 0
            stats.cache += step["cache_read_tokens"] as? Int ?? 0
        }
        let result = stats
        cache.withLock { $0[url.path] = (date, size, result) }
        return (result, date)
    }

    private static let settingsChangePatterns: [NSRegularExpression] = [
        // "from X to ModelName." or "from X to ModelName (variant)."
        try? NSRegularExpression(pattern: #"Model Selection[^.]*?\bto\s+(.+?)(?:\.\s|$)"#, options: [.dotMatchesLineSeparators]),
        // "<USER_SETTINGS_CHANGE>...to ModelName..."
        try? NSRegularExpression(pattern: #"changed setting.*?Model.*?\bto\s+(.+?)(?:\.\s|\n|$)"#, options: [.dotMatchesLineSeparators]),
    ].compactMap { $0 }
    private static let geminiPattern = try? NSRegularExpression(pattern: #"\b(gemini-[\w.\-]+)"#)

    /// Extracts Gemini / Antigravity model names from transcript content text.
    ///
    /// Handles two patterns:
    /// 1. `USER_SETTINGS_CHANGE` blocks: "The user changed setting `Model Selection` from X to Y."
    /// 2. `<model>` XML tags or `"model": "..."` JSON fragments embedded in content.
    private static func extractModelsFromContent(_ content: String, into models: inout Set<String>) {
        // Pattern 1: USER_SETTINGS_CHANGE with Model Selection.
        // Match: "from X to Y" where Y is the current model selection.
        if content.contains("Model Selection") || content.contains("model_selection") {
            // Extract the "to" model name: "from ... to ModelName" or "from None to ModelName (Thinking)."
            for regex in settingsChangePatterns {
                let range = NSRange(content.startIndex..., in: content)
                if let match = regex.firstMatch(in: content, range: range),
                   let modelRange = Range(match.range(at: 1), in: content) {
                    let raw = String(content[modelRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ".'\""))
                    if !raw.isEmpty, raw != "None", raw.count < 100 {
                        models.insert(raw)
                    }
                }
            }
        }

        // Pattern 2: Gemini model identifiers in content (e.g. "gemini-2.0-flash", "gemini-1.5-pro").
        if content.contains("gemini") {
            let range = NSRange(content.startIndex..., in: content)
            geminiPattern?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let match, let modelRange = Range(match.range(at: 1), in: content) {
                    models.insert(String(content[modelRange]))
                }
            }
        }
    }

    private static func readSync() -> AIProviderUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini")
        let antigravityDir = geminiDir.appendingPathComponent("antigravity")
        // Antigravity's sign-in file holds credentials, so it is never opened.
        let appInstalled = FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
            || FileManager.default.fileExists(atPath: antigravityDir.path)

        guard appInstalled else {
            return AIProviderUsage(
                provider: .antigravity,
                status: .unconfigured("Antigravity isn't installed on this Mac."),
                attribution: "Google Antigravity"
            )
        }

        let info = scanTranscripts()

        let sessionTotal = info.latestSessionInput + info.latestSessionOutput

        // Build token breakdown
        let tokens: AITokenBreakdown? = sessionTotal > 0 ? AITokenBreakdown(
            promptTokens: info.latestSessionInput,
            completionTokens: info.latestSessionOutput,
            cacheReadTokens: info.latestSessionCache > 0 ? info.latestSessionCache : nil,
            cacheWriteTokens: nil,
            totalTokens: sessionTotal
        ) : nil

        // Local transcripts do not report per-model quotas or context limits.
        // Never infer them from token counts or assume all models share a pool.
        let windows: [AIUsageWindow] = []

        return AIProviderUsage(
            provider: .antigravity,
            status: .active,
            plan: "Google Antigravity",
            model: info.modelName,
            windows: windows,
            tokens: tokens,
            lastUpdated: Date(),
            attribution: "Local Antigravity Session (~/.gemini)"
        )
    }
}
