import SwiftUI

/// Make categories in a couple of taps: type a name and press return, or tap a suggestion.
/// The sheet stays open so several can be added in a row, and Done jumps to the newest one.
struct QuickCategorySheet: View {
    /// Called when the sheet closes, with the category added last (if any).
    var onFinish: (TaskCategory?) -> Void
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.todoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @FocusState private var focused: Bool
    @State private var name = ""
    @State private var added: [TaskCategory] = []

    private static let ideas = ["Work", "Personal", "Shopping", "Health", "Study", "Home", "Travel", "Ideas",
                                "Fitness", "Finance", "Family", "Projects", "Reading", "Goals"]
    private static let limit = 24

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { store.validCategoryTitle(trimmed) }
    private var suggestions: [String] { Self.ideas.filter { store.validCategoryTitle($0) } }
    private var problem: String? {
        guard !trimmed.isEmpty, !valid else { return nil }
        return "You already have a category called “\(trimmed)”."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4)
                    }
                    if !added.isEmpty { addedSection }
                    if !suggestions.isEmpty { suggestionSection }
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AmbientBackground() }
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if valid { create(trimmed) }
                        dismiss()
                    }
                }
            }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "-demoCategoryName"), args.indices.contains(index + 1) { name = args[index + 1] }
                #endif
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { onFinish(added.last) }
    }

    // MARK: Pieces

    private var field: some View {
        HStack(spacing: 14) {
            // The icon the category will get, updating as you type.
            Image(systemName: trimmed.isEmpty ? "plus" : CategoryIcon.suggest(for: trimmed))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(trimmed.isEmpty ? Color.secondary : theme.deep)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .glassEffect(.regular.tint(theme.accent.opacity(0.25)), in: Circle())
                .accessibilityHidden(true)
            TextField("Name your category", text: $name)
                .font(.system(.title3, weight: .medium))
                .focused($focused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { if valid { create(trimmed) } }
                .onChange(of: name) { _, new in
                    if new.count > Self.limit { name = String(new.prefix(Self.limit)) }
                }
            Button { create(trimmed) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(valid ? theme.deep : Color.secondary.opacity(0.35))
                    .symbolEffect(.bounce, value: added.count)
            }
            .buttonStyle(.plain).disabled(!valid)
            .accessibilityLabel("Add category")
        }
        .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 12)
        .modifier(GlassCard())
    }

    private var addedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(TodoPalette.done)
            FlowChips(items: added.map { Chip(title: $0.title, symbol: $0.symbol) }, tint: TodoPalette.done, action: nil)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ADD").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            FlowChips(items: suggestions.map { Chip(title: $0, symbol: CategoryIcon.suggest(for: $0)) }, tint: theme.accent) { chip in
                create(chip.title)
            }
        }
    }

    private func create(_ title: String) {
        guard store.addCategory(title: title), let created = store.categories.last else { return }
        RewardFeedback.shared.added(haptics: hapticsEnabled)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25)) { added.append(created) }
        name = ""
        focused = true
    }
}

private struct Chip: Identifiable {
    let title: String
    let symbol: String
    var id: String { title }
}

/// Chips that wrap onto new lines. With an action they are buttons; without, plain labels.
private struct FlowChips: View {
    let items: [Chip]
    let tint: Color
    let action: ((Chip) -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items) { chip in
                if let action {
                    Button { action(chip) } label: { label(chip) }.buttonStyle(.plain)
                } else {
                    label(chip)
                }
            }
        }
    }

    private func label(_ chip: Chip) -> some View {
        HStack(spacing: 6) {
            Image(systemName: chip.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
            Text(chip.title).font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.14)).interactive(action != nil), in: Capsule())
    }
}
