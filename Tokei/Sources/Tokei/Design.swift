import SwiftUI

// 设计系统:颜色 / 间距 / 圆角集中定义,组件语义化复用。
enum Theme {
    static let claude = Color(red: 0.97, green: 0.57, blue: 0.31)
    static let codex  = Color(red: 0.23, green: 0.76, blue: 0.66)

    static let panelWidth: CGFloat = 322
    static let cardRadius: CGFloat = 16
    static let outerPad: CGFloat = 15

    static var brand: LinearGradient {
        LinearGradient(colors: [claude, codex], startPoint: .leading, endPoint: .trailing)
    }
}

// 毛玻璃之上的浮起卡片:淡色填充 + 渐变描边 + 柔和投影。
struct Card<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(tint.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [tint.opacity(0.40), tint.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.16), radius: 9, x: 0, y: 4)
    }
}

// 命中率环形仪表 —— 卡片视觉焦点之一。
struct RingGauge: View {
    var value: Double            // 0...100
    var tint: Color
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value / 100)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.55), radius: 3)
            VStack(spacing: -1) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("%")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

// 细进度条(配额用)。
struct MiniBar: View {
    var value: Double            // 0...100
    var tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(3, geo.size.width * min(1, value / 100)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.45), value: value)
    }
}

// 指标格子:图标 + 标签 + 等宽数值。
struct MetricCell: View {
    var icon: String
    var label: String
    var value: String
    var tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 21, height: 21)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
    }
}

// 大号成本焦点行。
struct CostHeadline: View {
    var cost: Double
    var caption: String
    var tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(String(format: "$%.2f", cost))
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }
}

// 自定义滑动分段控件(替代原生 segmented),选中态滑动高亮。
struct SegmentedTabs: View {
    @Binding var sel: RangeKey
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(RangeKey.allCases) { k in
                let on = k == sel
                Text(k.label)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { sel = k }
                    }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// 底部图标按钮,带 hover 高亮。
struct IconButton: View {
    var icon: String
    var label: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hover ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
