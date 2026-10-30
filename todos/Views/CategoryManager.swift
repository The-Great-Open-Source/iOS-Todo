import SwiftUI

struct CategoryManager: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TaskCategory?
    @State private var name = ""
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.categories) { category in
                        HStack(spacing: 12) {
                            Button {
                                store.setMain(category, enabled: !store.mainCategoryIDs.contains(category.id))
                            } label: {
                                Image(systemName: store.mainCategoryIDs.contains(category.id) ? "star.fill" : "star")
                                    .foregroundStyle(store.mainCategoryIDs.contains(category.id) ? Color.orange : Color.secondary)
                                    .frame(width: 36, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .disabled(pinDisabled(category))
                            .accessibilityLabel("\(store.mainCategoryIDs.contains(category.id) ? "Remove" : "Show") \(category.title) \(store.mainCategoryIDs.contains(category.id) ? "from" : "on") main screen")
                            Label(category.title, systemImage: category.symbol)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if category == .today {
                                Text("Default").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Menu {
                                    Button("Rename", systemImage: "pencil") {
                                        editing = category
                                        name = category.title
                                        showingEditor = true
                                    }
                                    Button("Remove · move tasks to Today", systemImage: "minus.circle", role: .destructive) {
                                        store.removeCategory(category)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Options for \(category.title)")
                            }
                        }
                    }
                } header: {
                    Text("Main screen · \(store.mainCategoryIDs.count) of 3")
                } footer: {
                    Text("Star up to three categories to list them first in the tab bar; the others follow, and you can swipe through all of them. Unstar one to make room for another. Today can be unstarred, but cannot be renamed or removed.")
                }
                Section {
                    Button("Add Category", systemImage: "plus") {
                        editing = nil
                        name = ""
                        showingEditor = true
                    }
                } footer: {
                    Text("Create as many categories as you need. Removing a category moves its tasks to Today.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(editing == nil ? "New Category" : "Rename Category", isPresented: $showingEditor) {
                TextField("Category name", text: $name)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let editing { store.renameCategory(editing, title: name) }
                    else { store.addCategory(title: name) }
                }
                .disabled(!store.validCategoryTitle(name, excluding: editing))
            } message: {
                Text("Choose a unique name, up to 24 characters. An icon is picked from the name.")
            }
            .alert("Couldn’t save categories", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    private func pinDisabled(_ category: TaskCategory) -> Bool {
        store.mainCategoryIDs.contains(category.id)
            ? store.mainCategoryIDs.count == 1
            : store.mainCategoryIDs.count == 3
    }
}
