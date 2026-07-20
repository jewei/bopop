import AppKit
import BopopKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Shortcut") {
                HotkeyRecorderView(
                    hotkey: $model.hotkey,
                    isRecording: $model.isRecording
                )
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())

                if model.spotlightConflict, model.hotkey == .default {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "⌘Space is also assigned to Spotlight.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)

                        HStack {
                            Button("Open Keyboard Settings") {
                                NSWorkspace.shared.open(
                                    SpotlightConflict.keyboardSettingsURL
                                )
                            }
                            Button("Re-check") {
                                model.recheckConflict()
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Clipboard") {
                Stepper(
                    "Keep last \(model.clipboardLimit) items",
                    value: $model.clipboardLimit,
                    in: 10...500,
                    step: 10
                )
            }

            Section("Translation") {
                Picker("Chinese variant", selection: $model.chineseVariant) {
                    Text("Simplified Chinese").tag(TranslationTarget.chineseSimplified)
                    Text("Traditional Chinese").tag(TranslationTarget.chineseTraditional)
                }
            }

            Section("Search") {
                Picker("Search engine", selection: $model.searchEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            }

            Section("General") {
                Toggle("Launch Bopop at login", isOn: $model.launchAtLogin)
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Color(nsColor: .bopopAccent))
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 380, height: 360)
    }
}
