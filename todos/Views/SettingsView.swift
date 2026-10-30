import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("showCompleted") private var showCompleted = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @State private var showingCategories = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Make yourself at home") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                    Toggle("Show completed tasks", isOn: $showCompleted)
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    Toggle("Celebration sounds", isOn: $soundEnabled)
                }
                Section {
                    Button("Categories") { showingCategories = true }
                } footer: {
                    Text("Completed tasks disappear from your checklist after 10 minutes and remain available under Completed tasks. Today does not reset at midnight.")
                }
                Section {
                    LabeledContent("Todos", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } footer: {
                    Text("A little space for what matters.\nYour tasks stay on this device, with a private backup that survives reinstalling the app.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .sheet(isPresented: $showingCategories) { CategoryManager() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
