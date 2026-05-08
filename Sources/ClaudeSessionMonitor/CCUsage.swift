import Foundation

struct CCUsageResponse: Decodable {
    let blocks: [Block]
}

struct Block: Decodable {
    let id: String
    let startTime: Date
    let endTime: Date
    let actualEndTime: Date?
    let isActive: Bool
    let isGap: Bool
    let totalTokens: Int
    let costUSD: Double
    let burnRate: BurnRate?
    let projection: Projection?
    let tokenLimitStatus: TokenLimitStatus?
}

struct BurnRate: Decodable {
    let tokensPerMinute: Double
    let costPerHour: Double
}

struct Projection: Decodable {
    let totalTokens: Int
    let totalCost: Double
    let remainingMinutes: Int
}

struct TokenLimitStatus: Decodable {
    let limit: Int
    let projectedUsage: Int
    let percentUsed: Double
    let status: String
}

struct SessionSnapshot {
    let blockId: String
    let currentPercent: Double
    let projectedPercent: Double
    let totalTokens: Int
    let limit: Int
    let costUSD: Double
    let endTime: Date
    let burnTokensPerMinute: Double?
    let projectedTotalCost: Double?
}

enum CCUsageError: Error, LocalizedError {
    case launcherNotFound
    case processFailed(Int32, String)
    case decodeFailed(String)
    case noActiveBlock

    var errorDescription: String? {
        switch self {
        case .launcherNotFound:
            return "Couldn't find npx/ccusage. Install Node and run `npm i -g ccusage` or ensure npx is on PATH."
        case .processFailed(let code, let stderr):
            return "ccusage exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decodeFailed(let detail):
            return "Failed to parse ccusage output: \(detail)"
        case .noActiveBlock:
            return "No active session — Claude Code hasn't been used in the current 5h window."
        }
    }
}

final class CCUsageClient {
    private let searchPaths: [String]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
        ]
        // Add latest nvm node bin if present.
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            let sorted = entries.sorted(by: >)
            for entry in sorted {
                paths.append("\(nvmRoot)/\(entry)/bin")
            }
        }
        // Also honor any PATH the process inherited.
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        self.searchPaths = paths
    }

    private func locate(_ binary: String) -> String? {
        for dir in searchPaths {
            let candidate = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Returns (executable, args). Prefers a globally installed `ccusage`, otherwise falls back to `npx ccusage@latest`.
    private func resolveLauncher() -> (String, [String])? {
        if let direct = locate("ccusage") {
            return (direct, [])
        }
        if let npx = locate("npx") {
            return (npx, ["--yes", "ccusage@latest"])
        }
        return nil
    }

    /// Augmented PATH for the spawned process so npx can find node.
    private var augmentedPATH: String {
        var dirs = searchPaths
        // Deduplicate while preserving order.
        var seen = Set<String>()
        dirs = dirs.filter { seen.insert($0).inserted }
        return dirs.joined(separator: ":")
    }

    func fetchActiveSnapshot() throws -> SessionSnapshot? {
        guard let (launcher, prefixArgs) = resolveLauncher() else {
            throw CCUsageError.launcherNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launcher)
        process.arguments = prefixArgs + [
            "blocks",
            "--active",
            "--token-limit", "max",
            "--json",
            "--offline", // avoid network round-trip for pricing data
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH
        // Quiet npx update notifier if we end up using it.
        env["NO_UPDATE_NOTIFIER"] = "1"
        env["CI"] = "1"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw CCUsageError.processFailed(process.terminationStatus, stderr)
        }

        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = formatter.date(from: raw) { return d }
            if let d = fallback.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
        }

        let response: CCUsageResponse
        do {
            response = try decoder.decode(CCUsageResponse.self, from: stdoutData)
        } catch {
            let preview = String(data: stdoutData, encoding: .utf8)?.prefix(400) ?? ""
            throw CCUsageError.decodeFailed("\(error) — output: \(preview)")
        }

        guard let active = response.blocks.first(where: { $0.isActive && !$0.isGap }) else {
            return nil
        }
        guard let limitStatus = active.tokenLimitStatus, limitStatus.limit > 0 else {
            // Limit unknown (e.g. very first session ever). Treat as 0% so UI can still render.
            return SessionSnapshot(
                blockId: active.id,
                currentPercent: 0,
                projectedPercent: 0,
                totalTokens: active.totalTokens,
                limit: 0,
                costUSD: active.costUSD,
                endTime: active.endTime,
                burnTokensPerMinute: active.burnRate?.tokensPerMinute,
                projectedTotalCost: active.projection?.totalCost
            )
        }

        let currentPercent = Double(active.totalTokens) / Double(limitStatus.limit) * 100.0
        return SessionSnapshot(
            blockId: active.id,
            currentPercent: currentPercent,
            projectedPercent: limitStatus.percentUsed,
            totalTokens: active.totalTokens,
            limit: limitStatus.limit,
            costUSD: active.costUSD,
            endTime: active.endTime,
            burnTokensPerMinute: active.burnRate?.tokensPerMinute,
            projectedTotalCost: active.projection?.totalCost
        )
    }
}
