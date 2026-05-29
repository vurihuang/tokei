import Foundation

enum RangeKey: String, CaseIterable, Identifiable {
    case yesterday, today, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .week: return "本周"
        case .month: return "本月"
        }
    }
}

struct ClaudeModelStat: Codable, Identifiable {
    var name: String
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var cost: Double
    var id: String { name }
    var total: Int { `in` + out + cr + cw }
}

struct ClaudeRange: Codable {
    var hit: Double
    var `in`: Int
    var out: Int
    var cr: Int
    var cw: Int
    var cost: Double
    var models: [ClaudeModelStat] = []
}

struct ClaudeRanges: Codable {
    var today: ClaudeRange
    var yesterday: ClaudeRange
    var week: ClaudeRange
    var month: ClaudeRange
    func get(_ k: RangeKey) -> ClaudeRange {
        switch k {
        case .today: return today
        case .yesterday: return yesterday
        case .week: return week
        case .month: return month
        }
    }
}

struct ClaudeStat: Codable {
    var ranges: ClaudeRanges
    var session_name: String
    var session_total: Int
    var q5: Double?
    var q5_reset: Int?
    var q7: Double?
    var q7_reset: Int?
}

struct CodexRange: Codable {
    var hit: Double
    var `in`: Int
    var cached: Int
    var out: Int
    var reason: Int
    var cost: Double
}

struct CodexRanges: Codable {
    var today: CodexRange
    var yesterday: CodexRange
    var week: CodexRange
    var month: CodexRange
    func get(_ k: RangeKey) -> CodexRange {
        switch k {
        case .today: return today
        case .yesterday: return yesterday
        case .week: return week
        case .month: return month
        }
    }
}

struct CodexStat: Codable {
    var ranges: CodexRanges
    var p5: Double?
    var pw: Double?
    var r5: Int?
    var rw: Int?
    var plan: String?
}

struct Usage: Codable {
    var claude: ClaudeStat
    var codex: CodexStat
}

enum Fmt {
    static func human(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    static func reset(_ epoch: Int?) -> String {
        guard let e = epoch else { return "?" }
        let d = Date(timeIntervalSince1970: TimeInterval(e))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}
