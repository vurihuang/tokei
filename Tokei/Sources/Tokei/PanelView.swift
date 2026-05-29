import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var store: Store
    @State private var sel: RangeKey = .today
    @State private var modelsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if let u = store.usage {
                SegmentedTabs(sel: $sel)
                Card(tint: Theme.claude) { claudeBlock(u.claude, u.claude.ranges.get(sel)) }
                Card(tint: Theme.codex)  { codexBlock(u.codex, u.codex.ranges.get(sel)) }
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 90)
            }
            footer
        }
        .padding(Theme.outerPad)
        .frame(width: Theme.panelWidth)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - 品牌头部
    var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 0) {
                Text("Tokei")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(0.5)
                Text("时计 · AI 用量")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(store.lastUpdated)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Claude 卡片
    @ViewBuilder
    func claudeBlock(_ c: ClaudeStat, _ r: ClaudeRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Claude Code", tint: Theme.claude, hit: r.hit)
            CostHeadline(cost: r.cost, caption: "\(sel.label) ≈成本", tint: Theme.claude)
            metricGrid([
                (.init("arrow.down", "输入", Fmt.human(r.in))),
                (.init("arrow.up", "输出", Fmt.human(r.out))),
                (.init("bolt.fill", "缓存读", Fmt.human(r.cr))),
                (.init("square.stack.3d.up.fill", "缓存写", Fmt.human(r.cw))),
            ], tint: Theme.claude)
            if !r.models.isEmpty { modelDisclosure(r.models) }
            if c.q5 != nil || c.q7 != nil { thinDivider }
            if let q5 = c.q5 {
                quotaRow(title: "5h 剩余", pct: 100 - q5, reset: c.q5_reset, tint: Theme.claude)
            }
            if let q7 = c.q7 {
                quotaRow(title: "周剩余", pct: 100 - q7, reset: c.q7_reset, tint: Theme.claude)
            }
            sessionRow(c.session_name, c.session_total)
            disclaimer
        }
    }

    // MARK: - Codex 卡片
    @ViewBuilder
    func codexBlock(_ x: CodexStat, _ r: CodexRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Codex", tint: Theme.codex, hit: r.hit)
            CostHeadline(cost: r.cost, caption: "\(sel.label) ≈成本", tint: Theme.codex)
            metricGrid({
                var items: [Metric] = [
                    .init("arrow.down", "输入", Fmt.human(r.in)),
                    .init("bolt.fill", "缓存读", Fmt.human(r.cached)),
                    .init("arrow.up", "输出", Fmt.human(r.out)),
                ]
                if r.reason > 0 { items.append(.init("brain", "推理", Fmt.human(r.reason))) }
                return items
            }(), tint: Theme.codex)
            if x.p5 != nil || x.pw != nil { thinDivider }
            if let p5 = x.p5 {
                quotaRow(title: "5h 剩余", pct: 100 - p5, reset: x.r5, tint: Theme.codex)
            }
            if let pw = x.pw {
                quotaRow(title: "周剩余", pct: 100 - pw, reset: x.rw, tint: Theme.codex)
            }
            if let plan = x.plan {
                HStack {
                    Text("plan").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.codex.opacity(0.16)))
                }
            }
            disclaimer
        }
    }

    // MARK: - 复用片段
    struct Metric { var icon, label, value: String
        init(_ i: String, _ l: String, _ v: String) { icon = i; label = l; value = v } }

    func cardHead(_ title: String, tint: Color, hit: Double) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Circle().fill(tint.gradient).frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.6), radius: 3)
                Text(title).font(.system(size: 14, weight: .bold))
            }
            Spacer()
            HStack(spacing: 6) {
                Text("命中").font(.system(size: 9)).foregroundStyle(.tertiary)
                RingGauge(value: hit, tint: tint, size: 38)
            }
        }
    }

    func metricGrid(_ items: [Metric], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: 9) {
            ForEach(items.indices, id: \.self) { i in
                MetricCell(icon: items[i].icon, label: items[i].label,
                           value: items[i].value, tint: tint)
            }
        }
    }

    var thinDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    func sessionRow(_ name: String, _ total: Int) -> some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            Text("本会话 \(name)").font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Text(Fmt.human(total))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    var disclaimer: some View {
        Text("按 API 价估,非订阅实付")
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
    }

    @ViewBuilder
    func modelDisclosure(_ models: [ClaudeModelStat]) -> some View {
        Button {
            modelsOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9)).foregroundStyle(Theme.claude)
                Text("按模型 (\(models.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $modelsOpen, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 9) {
                Text("按模型 · \(sel.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(models) { m in
                    HStack {
                        Circle().fill(Theme.claude.opacity(0.7)).frame(width: 5, height: 5)
                        Text(m.name).font(.system(size: 11.5))
                        Spacer(minLength: 18)
                        Text(String(format: "$%.2f", m.cost))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        Text("· \(Fmt.human(m.total))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(width: 238)
            .environment(\.colorScheme, .dark)
        }
    }

    func quotaRow(title: String, pct: Double, reset: Int?, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pct <= 15 ? .red : .primary)
                Text("· \(Fmt.reset(reset))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            MiniBar(value: pct, tint: pct <= 15 ? .red : tint)
        }
    }

    var footer: some View {
        HStack(spacing: 4) {
            Spacer()
            IconButton(icon: "arrow.clockwise", label: "刷新") { store.refresh() }
            IconButton(icon: "power", label: "退出") { NSApp.terminate(nil) }
        }
    }
}
