// Sources/FrenchLiveCore/Settings/SettingsSheet.swift
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("Recognition") {
                    Picker("Source Language", selection: $settings.sourceLanguage) {
                        ForEach(SettingsStore.sourceLanguages) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Translation") {
                    Picker("Target Language", selection: $settings.targetLanguage) {
                        ForEach(SettingsStore.targetLanguages) { lang in
                            Text(lang.label).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Files") {
                    HStack {
                        Text(shortenedPath(settings.outputFolderPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Section("Session") {
                    Picker("Auto-save", selection: $settings.autoSaveInterval) {
                        Text("Off").tag(0)
                        Text("Every 5 min").tag(5)
                        Text("Every 10 min").tag(10)
                        Text("Every 30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380)
    }

    private func shortenedPath(_ path: String) -> String {
        let components = (path as NSString).pathComponents
        let last2 = components.suffix(2)
        return last2.isEmpty ? path : "…/" + last2.joined(separator: "/")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolderPath = url.path
        }
    }
}
