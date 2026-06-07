import SwiftUI

struct WrappedAchievement: Codable, Identifiable {
    var icon: String; var title: String; var desc: String
    var tint: String = "coral"
    var id: String { title }
}

struct WrappedProject: Codable, Identifiable {
    var name: String; var tokens: Int; var cost: Double
    var id: String { name }
}

struct WrappedBusiest: Codable { var date = ""; var tokens = 0 }
struct WrappedModel: Codable { var name = "-"; var tokens = 0 }

struct WrappedData: Codable {
    var total_tokens = 0
    var total_cost: Double = 0
    var active_days = 0
    var streak_max = 0
    var streak_cur = 0
    var busiest = WrappedBusiest()
    var top_model = WrappedModel()
    var hours: [Int] = []
    var weekday: [Int] = []
    var projects: [WrappedProject] = []
    var max_projs_day = 0
    var night_share: Double = 0
    var first_day = ""
    var achievements: [WrappedAchievement] = []
}

// Tokei 回顾 —— 作息 / 项目 / 连续 / 成就(Claude 数据)。
struct WrappedView: View {
    let data: WrappedData
    @State private var achievementsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero(data)
            statChips(data)
            if !data.achievements.isEmpty { achievementsSection(data) }
            Divider().opacity(0.15)
            rhythmSection(data)
        }
    }

    // MARK: - Hero
    func hero(_ d: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.claude)
                Text("回顾").font(.system(size: 11, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Theme.tSecondary)
                Spacer()
                if !d.first_day.isEmpty {
                    Text("自 \(d.first_day) · \(d.active_days) 天活跃")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.human(d.total_tokens))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Theme.claude, Theme.gemini],
                                                    startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
                Text("tokens").font(.system(size: 10.5)).foregroundStyle(Theme.tTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.claude.opacity(0.16), Theme.gemini.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.claude.opacity(0.12), lineWidth: 0.75))
        )
    }

    // MARK: - Stat chips
    func statChips(_ d: WrappedData) -> some View {
        let avg = d.active_days > 0 ? d.total_cost / Double(d.active_days) : 0
        return HStack(spacing: 7) {
            chip("总成本", "$" + intStr(d.total_cost), Theme.claude)
            chip("连续", "\(d.streak_cur) 天", Theme.hermes, icon: "flame.fill")
            chip("日均", "$" + intStr(avg), Theme.gemini)
            chip("峰值日", shortDate(d.busiest.date), Color.red.opacity(0.85))
            chip("本命模型", d.top_model.name, Theme.codex)
        }
    }

    func chip(_ label: String, _ value: String, _ tint: Color, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(tint.opacity(0.9))
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
                Text(value).font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7).padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    // MARK: - Achievements
    func achievementsSection(_ d: WrappedData) -> some View {
        let limit = 10
        let hasMore = d.achievements.count > limit
        let shown = (achievementsExpanded || !hasMore) ? d.achievements : Array(d.achievements.prefix(limit))
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("成就").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.tPrimary)
                Text("\(d.achievements.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.claude)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.claude.opacity(0.14)))
                Spacer()
                if hasMore {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { achievementsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(achievementsExpanded ? "收起" : "展开全部")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: achievementsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Theme.tTertiary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                      spacing: 7) {
                ForEach(shown) { a in badge(a) }
            }
        }
    }

    func badge(_ a: WrappedAchievement) -> some View {
        HStack(spacing: 8) {
            Image(systemName: a.icon).font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(LinearGradient(colors: [Theme.claude, Theme.claude.opacity(0.6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: Theme.claude.opacity(0.4), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.tPrimary)
                Text(a.desc).font(.system(size: 9)).foregroundStyle(Theme.tTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 24h rhythm
    func rhythmSection(_ d: WrappedData) -> some View {
        let maxH = max(d.hours.max() ?? 1, 1)
        let peak = d.hours.firstIndex(of: d.hours.max() ?? 0) ?? -1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活跃时段").font(.system(size: 13, weight: .bold))
                Spacer()
                if peak >= 0 {
                    Text(String(format: "高峰 %02d:00", peak))
                        .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                }
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    let v = h < d.hours.count ? d.hours[h] : 0
                    let ratio = CGFloat(v) / CGFloat(maxH)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == peak ? AnyShapeStyle(Theme.claude.gradient)
                                        : AnyShapeStyle(Theme.claude.opacity(0.32)))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, 48 * ratio))
                }
            }
            .frame(height: 48, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 23], id: \.self) { h in
                    Text("\(h)").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.tTertiary)
                    if h != 23 { Spacer() }
                }
            }
        }
    }

    // MARK: - helpers
    func intStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))"
    }
    func shortDate(_ s: String) -> String { s.count >= 10 ? String(s.suffix(5)) : s }
}
