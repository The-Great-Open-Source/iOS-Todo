import SwiftUI

private struct Arrival {
    var scale = 1.0
    var glow = 0.0
}

struct TaskRow: View {
    let task: TaskItem
    var arrived = false
    let toggle: () -> Void
    var edit: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todoTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: toggle) {
                Bead(done: task.isCompleted)
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")
            .accessibilityValue(task.isCompleted ? "Completed" : "Incomplete")

            Text(task.title)
                .font(.system(.title3, weight: .medium))
                .tracking(-0.4)
                .strikethrough(task.isCompleted, pattern: .solid, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .onTapGesture(perform: edit)
        }
        .padding(.leading, 13).padding(.trailing, 22).padding(.vertical, 13)
        .modifier(GlassTile(tint: task.category.accent))
        .keyframeAnimator(initialValue: Arrival(), trigger: arrived) { [live = arrived && !reduceMotion, accent = theme.accent] view, fx in
            view
                .scaleEffect(live ? fx.scale : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent, lineWidth: 2.5)
                        .opacity(live ? fx.glow : 0)
                        .shadow(color: accent.opacity(live ? fx.glow : 0), radius: 14)
                        .allowsHitTesting(false)
                }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.045, duration: 0.2)
                SpringKeyframe(1.0, duration: 0.7, spring: .bouncy)
            }
            KeyframeTrack(\.glow) {
                LinearKeyframe(1.0, duration: 0.15)
                CubicKeyframe(0.0, duration: 1.2)
            }
        }
        .opacity(task.isCompleted ? 0.78 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12), value: task.isCompleted)
        .accessibilityElement(children: .contain)
    }
}

/// A plain ring that fills and draws its check when done.
private struct Bead: View {
    let done: Bool
    @Environment(\.todoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(TodoPalette.done).scaleEffect(done ? 1 : 0.3).opacity(done ? 1 : 0)
            Circle().strokeBorder(done ? Color.clear : Color.primary.opacity(0.22), lineWidth: 1.5)
            CheckmarkShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                .frame(width: 13, height: 13)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(done ? 0.05 : 0), value: done)
        }
        .frame(width: 27, height: 27)
        .phaseAnimator([1.0, 1.14, 1.0], trigger: done) { view, scale in
            view.scaleEffect(done ? scale : 1)
        } animation: { _ in
            reduceMotion ? .linear(duration: 0) : .spring(duration: 0.22, bounce: 0.3)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2), value: done)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.96, y: rect.minY + rect.height * 0.14))
        return path
    }
}

/// Every category as a tab. The selected one is a piece of Liquid Glass that flows between pills.
/// Names never wrap: they truncate, and with many tabs the strip scrolls and keeps the selection centred.
struct CategorySelector: View {
    let categories: [TaskCategory]
    @Binding var selection: TaskCategory
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) { pills }.padding(4)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 2) { pills }.padding(4)
                    }
                    .scrollIndicators(.hidden)
                    .mask(
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                               .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .onChange(of: selection) { _, new in withAnimation(.snappy) { proxy.scrollTo(new.id, anchor: .center) } }
                    .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
                }
            }
            .background { Capsule().fill(.primary.opacity(scheme == .dark ? 0.05 : 0.04)) }
        }
    }

    @ViewBuilder
    private var pills: some View {
        ForEach(categories) { category in
            let selected = selection == category
            Button {
                if !selected { selection = category }
            } label: {
                segment(category, selected: selected)
            }
            .buttonStyle(.plain)
            .modifier(SelectedGlass(selected: selected, namespace: glass))
            .id(category.id)
            .accessibilityLabel(category.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func segment(_ category: TaskCategory, selected: Bool) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    Image(systemName: category.symbol)
                    Text(category.title)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: category.symbol).font(.system(size: 13, weight: .medium))
                    Text(category.title)
                }
            }
        }
        .lineLimit(1).truncationMode(.tail)
        .font(.system(.subheadline, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .frame(maxWidth: 260)
        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
        .contentShape(Capsule())
    }
}

private struct SelectedGlass: ViewModifier {
    let selected: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if selected {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("selection", in: namespace)
        } else {
            content
        }
    }
}

/// A small paper-and-glass composition, drawn natively at every display scale.
struct EmptyChecklistIllustration: View {
    @Environment(\.todoTheme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23)
                .fill(.primary.opacity(0.035))
                .frame(width: 150, height: 110).rotationEffect(.degrees(-12)).offset(x: -5, y: -5)
            VStack(spacing: 15) {
                ForEach(0..<3) { index in
                    HStack(spacing: 12) {
                        Image(systemName: index == 0 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(index == 0 ? theme.accent : Color.secondary.opacity(0.35))
                        Capsule().fill(.primary.opacity(index == 0 ? 0.16 : 0.07))
                            .frame(width: index == 1 ? 55 : 72, height: 4)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(24).frame(width: 160, height: 132)
            .modifier(GlassCard()).rotationEffect(.degrees(7))
        }
        .frame(width: 220, height: 180).accessibilityHidden(true)
    }
}
