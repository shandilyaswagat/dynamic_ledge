import Foundation

/// Reads the local Google Antigravity session and token metrics from `~/.gemini`, without transmitting credentials.
public enum AntigravityUsageReader {
    public static func read() async -> AIProviderUsage {
        // Always read transcripts for model info, even when quota service is available.
        let transcriptInfo = await Task.detached(priority: .utility) { scanTranscripts() }.value
        if var quota = await AntigravityQuotaReader.read() {
            // Enrich quota result with model names discovered from transcripts.
            if quota.model == nil, let model = transcriptInfo.modelName {
                quota = AIProviderUsage(
                    provider: quota.provider,
                    status: quota.status,
                    accountName: quota.accountName ?? transcriptInfo.accountEmail,
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
        return await Task.detached(priority: .utility) {
            readSync(transcriptInfo: transcriptInfo)
        }.value
    }

    /// Intermediate result from scanning transcript files.
    private struct TranscriptInfo: Sendable {
        var observedModels: Set<String> = []
        var accountEmail: String?
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
            // Try both compact and full transcript files.
            let logsDir = dir
                .appendingPathComponent(".system_generated")
                .appendingPathComponent("logs")
            let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")
            let fullTranscriptURL = logsDir.appendingPathComponent("transcript_full.jsonl")

            guard FileManager.default.fileExists(atPath: transcriptURL.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path),
                  let modDate = attributes[.modificationDate] as? Date,
                  let data = try? Data(contentsOf: transcriptURL),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            info.hasTranscripts = true
            let isTodayConv = modDate >= today
            var dirInput = 0
            var dirOutput = 0
            var dirCache = 0

            content.enumerateLines { line, _ in
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let step = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return
                }

                // 1. Check top-level model fields (present in some transcript versions).
                for key in ["model", "model_id", "modelId", "model_name"] {
                    if let model = step[key] as? String, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        info.observedModels.insert(model)
                    }
                }

                // 2. Extract model from USER_SETTINGS_CHANGE blocks in content.
                //    These appear as: "The user changed setting `Model Selection` from X to Y (Thinking)."
                if let stepContent = step["content"] as? String {
                    Self.extractModelsFromContent(stepContent, into: &info.observedModels)
                }

                // 3. Accumulate token counts.
                let inp = step["input_tokens"] as? Int ?? 0
                let out = step["output_tokens"] as? Int ?? 0
                let cache = step["cache_read_tokens"] as? Int ?? 0

                dirInput += inp
                dirOutput += out
                dirCache += cache
            }

            // If the compact transcript had truncated content fields and we found no models yet,
            // try the full transcript for model info only (it's larger, so we scan selectively).
            if info.observedModels.isEmpty,
               FileManager.default.fileExists(atPath: fullTranscriptURL.path),
               let fullData = try? Data(contentsOf: fullTranscriptURL),
               let fullContent = String(data: fullData, encoding: .utf8) {
                fullContent.enumerateLines { line, stop in
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let step = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        return
                    }
                    for key in ["model", "model_id", "modelId", "model_name"] {
                        if let model = step[key] as? String, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            info.observedModels.insert(model)
                        }
                    }
                    if let stepContent = step["content"] as? String {
                        Self.extractModelsFromContent(stepContent, into: &info.observedModels)
                    }
                }
            }

            if isFirst {
                info.latestSessionInput = dirInput
                info.latestSessionOutput = dirOutput
                info.latestSessionCache = dirCache
                isFirst = false
            }

            if isTodayConv {
                info.todayInput += dirInput
                info.todayOutput += dirOutput
                info.todayCache += dirCache
            }
        }

        return info
    }

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
            let patterns = [
                // "from X to ModelName." or "from X to ModelName (variant)."
                try? NSRegularExpression(pattern: #"Model Selection[^.]*?\bto\s+(.+?)(?:\.\s|$)"#, options: [.dotMatchesLineSeparators]),
                // "<USER_SETTINGS_CHANGE>...to ModelName..."
                try? NSRegularExpression(pattern: #"changed setting.*?Model.*?\bto\s+(.+?)(?:\.\s|\n|$)"#, options: [.dotMatchesLineSeparators]),
            ]
            for regex in patterns.compactMap({ $0 }) {
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
            let geminiPattern = try? NSRegularExpression(pattern: #"\b(gemini-[\w.\-]+)"#)
            let range = NSRange(content.startIndex..., in: content)
            geminiPattern?.enumerateMatches(in: content, range: range) { match, _, _ in
                if let match, let modelRange = Range(match.range(at: 1), in: content) {
                    models.insert(String(content[modelRange]))
                }
            }
        }
    }

    private static func readSync(transcriptInfo: TranscriptInfo? = nil) -> AIProviderUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini")
        let tokenFile = geminiDir.appendingPathComponent("jetski-standalone-oauth-token")
        let antigravityDir = geminiDir.appendingPathComponent("antigravity")

        var accountEmail: String?
        var authMethod: String = "Consumer"
        var isSignedIn = false

        // 1. Read OAuth token metadata if present
        if FileManager.default.fileExists(atPath: tokenFile.path),
           let data = try? Data(contentsOf: tokenFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            accountEmail = json["id_token_email"] as? String
            if let method = json["auth_method"] as? String, !method.isEmpty {
                authMethod = method.capitalized
            }
            if accountEmail != nil || json["token"] != nil {
                isSignedIn = true
            }
        }

        // 2. Check if Antigravity application or directory exists
        let appInstalled = FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
            || FileManager.default.fileExists(atPath: antigravityDir.path)

        guard appInstalled || isSignedIn else {
            return AIProviderUsage(
                provider: .antigravity,
                status: .unconfigured("Antigravity is not installed or signed in on this Mac."),
                attribution: "Google Antigravity"
            )
        }

        // 3. Use pre-scanned transcript info or scan now
        let info = transcriptInfo ?? scanTranscripts()

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

        let planName = "Google Antigravity (\(authMethod))"

        return AIProviderUsage(
            provider: .antigravity,
            status: .active,
            accountName: accountEmail,
            plan: planName,
            model: info.modelName,
            windows: windows,
            tokens: tokens,
            lastUpdated: Date(),
            attribution: "Local Antigravity Session (~/.gemini)"
        )
    }
}
