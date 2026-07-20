import AppKit
import BopopKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var newSearchName = ""
    @State private var newSearchKeyword = ""
    @State private var newSearchTemplate = ""
    @State private var selectedSnippetID: UUID?
    @State private var snippetName = ""
    @State private var snippetKeyword = ""
    @State private var snippetContent = ""

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

                ForEach(model.customSearches) { search in
                    HStack {
                        Text("\(search.keyword) — \(search.name)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            model.removeCustomSearch(id: search.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                TextField("Name", text: $newSearchName)
                TextField("Keyword", text: $newSearchKeyword)
                TextField("URL with {query}", text: $newSearchTemplate)
                Button {
                    let added = model.addCustomSearch(
                        name: newSearchName,
                        keyword: newSearchKeyword,
                        urlTemplate: newSearchTemplate
                    )
                    if added {
                        newSearchName = ""
                        newSearchKeyword = ""
                        newSearchTemplate = ""
                    }
                } label: {
                    Label("Add Search", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("File Search") {
                if model.fileSearchFolders.isEmpty {
                    Text("Searches your whole home folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.fileSearchFolders, id: \.self) { folder in
                        HStack {
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeFileSearchFolder(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button {
                    model.presentFileSearchFolderPicker()
                } label: {
                    Label("Add Folder…", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("Snippets") {
                ForEach(model.snippets) { snippet in
                    HStack {
                        Text(snippet.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            model.removeSnippet(id: snippet.id)
                            if selectedSnippetID == snippet.id {
                                selectedSnippetID = nil
                                snippetName = ""
                                snippetKeyword = ""
                                snippetContent = ""
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSnippetID = snippet.id
                        snippetName = snippet.name
                        snippetKeyword = snippet.keyword ?? ""
                        snippetContent = snippet.content
                    }
                }

                TextField("Name", text: $snippetName)
                TextField("Keyword (optional)", text: $snippetKeyword)
                TextEditor(text: $snippetContent)
                    .frame(height: 80)
                    .font(.body)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )

                HStack {
                    Button {
                        let added = model.addSnippet(
                            name: snippetName,
                            keyword: snippetKeyword,
                            content: snippetContent
                        )
                        if added {
                            selectedSnippetID = nil
                            snippetName = ""
                            snippetKeyword = ""
                            snippetContent = ""
                        }
                    } label: {
                        Label("Add Snippet", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    if let selectedSnippetID,
                       let selected = model.snippets.first(where: { $0.id == selectedSnippetID }) {
                        Button("Save") {
                            model.updateSnippet(Snippet(
                                id: selected.id,
                                name: snippetName.trimmingCharacters(in: .whitespacesAndNewlines),
                                keyword: snippetKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : snippetKeyword.trimmingCharacters(in: .whitespacesAndNewlines),
                                content: snippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            ))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("Appearance") {
                HStack {
                    Text("Palette icon")
                    Spacer()
                    if model.hasCustomBrandImage {
                        Button("Reset to Default") {
                            model.resetBrandImageToDefault()
                        }
                    }
                    Button("Choose Image…") {
                        model.presentBrandImagePicker()
                    }
                }
                if let error = model.brandImageImportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 380, height: 530)
    }
}
