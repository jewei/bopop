import AppKit
import BopopKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var showingCurrencyConsent = false
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

                // Two different signals. `spotlightConflict` predicts one
                // known clash by reading Spotlight's own preferences; the
                // other is Carbon reporting that registration actually
                // failed, which catches any app holding the combination.
                // The second used to go only to the log, so Bopop ran with a
                // dead shortcut and nothing on screen said so.
                if model.spotlightConflict, model.hotkey == .default {
                    hotkeyWarning("⌘Space is also assigned to Spotlight.")
                } else if model.hotkeyUnavailable {
                    hotkeyWarning(
                        "This shortcut is already in use by another app, so it won't open Bopop."
                    )
                }
            }

            Section("Clipboard") {
                Stepper(
                    "Keep last \(model.clipboardLimit) unpinned items",
                    value: $model.clipboardLimit,
                    in: 10...500,
                    step: 10
                )
                Text(
                    "Pinned items are kept regardless of this limit, up to \(ClipboardStore.maximumPinnedEntries), and survive Clear Clipboard History."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !model.hiddenResultIDs.isEmpty {
                Section("Hidden results") {
                    ForEach(model.hiddenResultIDs, id: \.self) { id in
                        // Ids are "app:<bundle id or path>" — show the
                        // readable half rather than the storage key.
                        let readable = id.split(separator: ":", maxSplits: 1)
                            .last.map(String.init) ?? id
                        HStack {
                            Text(readable)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Unhide") { model.unhideResult(id) }
                                .controlSize(.small)
                                // Every row's button reads "Unhide" otherwise,
                                // so VoiceOver can't tell them apart.
                                .accessibilityLabel("Unhide \(readable)")
                        }
                    }
                    Text("Hide a result from the ⌘K actions panel to stop it appearing in search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Currency") {
                Toggle("Convert currencies", isOn: Binding(
                    get: { model.currencyEnabled },
                    set: { wantsOn in
                        // Turning ON routes through the disclosure below;
                        // turning OFF is immediate and clears cached rates.
                        if wantsOn {
                            showingCurrencyConsent = true
                        } else {
                            model.setCurrencyEnabled(false)
                        }
                    }
                ))
                Text("Off by default. When on, Bopop fetches exchange rates from frankfurter.dev — the only feature that contacts a server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alert("Fetch exchange rates?", isPresented: $showingCurrencyConsent) {
                Button("Cancel", role: .cancel) {}
                Button("Turn On") { model.setCurrencyEnabled(true) }
            } message: {
                Text("Bopop will request the daily rate table from frankfurter.dev when you type a conversion, and cache it locally.\n\nNo account, no identifiers, and nothing you type is sent — only a request for the table itself. Turning this off again deletes the cached rates.")
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
                        .help("Remove this search")
                        .accessibilityLabel("Remove search \(search.name)")
                    }
                }

                TextField("Name", text: $newSearchName)
                    .onChange(of: newSearchName) { model.clearCustomSearchError() }
                TextField("Keyword", text: $newSearchKeyword)
                    .onChange(of: newSearchKeyword) { model.clearCustomSearchError() }
                Text("\"f\", \"t\", and keywords starting with \":\" are reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("URL with {query}", text: $newSearchTemplate)
                    .onChange(of: newSearchTemplate) { model.clearCustomSearchError() }
                if let error = model.customSearchError {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                            if model.isFileSearchFolderMissing(folder) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("This folder is missing, so it is skipped when searching.")
                                    .accessibilityLabel("Missing folder")
                            }
                            Spacer()
                            Button {
                                model.removeFileSearchFolder(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this folder")
                            .accessibilityLabel(
                                "Remove folder \((folder as NSString).lastPathComponent)"
                            )
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
                if !model.snippetsAvailable {
                    Label(
                        SettingsModel.SnippetError.storageUnavailable.message,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
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
                        .help("Remove this snippet")
                        .accessibilityLabel("Remove snippet \(snippet.name)")
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
                    .onChange(of: snippetName) { model.clearSnippetError() }
                TextField("Keyword (optional)", text: $snippetKeyword)
                TextEditor(text: $snippetContent)
                    .frame(height: 80)
                    .font(.body)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                    .onChange(of: snippetContent) { model.clearSnippetError() }
                if let error = model.snippetError {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

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
                LabeledContent("Version", value: model.appVersion)
                HStack {
                    Button("Check for Updates…") {
                        model.checkForUpdates?()
                    }
                    if model.updateAvailable {
                        Text("Update available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(Color(nsColor: .bopopAccent))
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 380, height: 530)
    }

    @ViewBuilder
    private func hotkeyWarning(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            HStack {
                Button("Open Keyboard Settings") {
                    NSWorkspace.shared.open(SpotlightConflict.keyboardSettingsURL)
                }
                // Retries the registration too, so freeing the shortcut in the
                // other app and pressing this is enough — no relaunch.
                Button("Re-check") {
                    model.recheckConflict()
                }
            }
            .controlSize(.small)
        }
    }

}
