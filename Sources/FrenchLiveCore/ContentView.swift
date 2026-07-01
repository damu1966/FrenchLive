import SwiftUI

public struct ContentView: View {
    @StateObject private var store: TranscriptStore
    @StateObject private var sessionManager: SessionManager
    @StateObject private var settings: SettingsStore
    @State private var showingSettings = false
    @State private var showingHistory = false

    public init() {
        let store = TranscriptStore()
        let translator = Translator()
        let settings = SettingsStore()
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _sessionManager = StateObject(wrappedValue: SessionManager(store: store, translator: translator, settings: settings))
    }

    public var body: some View {
        if #available(macOS 15.0, *) {
            TranslationEnabledView(
                content: mainContent,
                translator: sessionManager.translator,
                sourceLanguage: settings.sourceLanguage,
                targetLanguage: settings.targetLanguage
            )
        } else {
            mainContent
        }
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 0) {
            sourcePickerBar
            Divider()
            transcriptScrollView
            Divider()
            controlBar
            Divider()
            statusBar
        }
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(settings: settings)
        }
        .sheet(isPresented: $showingHistory) {
            HistorySheet(folderPath: settings.outputFolderPath)
        }
    }

    // MARK: - Source picker

    private var sourcePickerBar: some View {
        HStack {
            Text("Source:")
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.selectedSource) {
                ForEach(AudioSourceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(sessionManager.state != .idle)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript scroll view

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.entries) { entry in
                        TranscriptRowView(entry: entry)
                            .id(entry.id)
                    }
                    if !store.liveText.isEmpty {
                        LiveRowView(text: store.liveText, source: store.liveSource)
                            .id("live")
                    }
                }
                .padding()
            }
            .onChange(of: store.entries.count) { _ in
                // anchor: .top so the full entry is visible from its first line,
                // not just its tail — long sentences were clipped at the bottom.
                withAnimation {
                    if let lastId = store.entries.last?.id {
                        proxy.scrollTo(lastId, anchor: .top)
                    } else {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
            }
            // Only scroll to live row when it first appears (liveText was empty
            // and is now non-empty). Avoids 5-10 animations/second during speech.
            .onChange(of: store.liveText.isEmpty) { isEmpty in
                if !isEmpty {
                    withAnimation { proxy.scrollTo("live", anchor: .bottom) }
                }
            }
            // Scroll to reveal each entry when its translation lands, so long
            // sentences aren't stuck off-screen showing "…" while the live row
            // has scrolled past them.
            .onChange(of: store.lastTranslatedId) { id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack {
            Button(action: togglePause) {
                Label(primaryButtonLabel, systemImage: primaryButtonIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryButtonTint)
            .disabled(sessionManager.state == .stopping)
            .keyboardShortcut(" ", modifiers: [])

            if sessionManager.state == .recording || sessionManager.state == .paused {
                Button(action: endSession) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(sessionManager.state == .stopping)
                .keyboardShortcut(".", modifiers: .command)
            }

            Spacer()

            Button("Clear") { store.clear() }
                .disabled(sessionManager.state != .idle)

            Button("Open Folder") { openTranscriptsFolder() }

            Button("History") { showingHistory = true }

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .disabled(sessionManager.state != .idle)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var primaryButtonLabel: String {
        switch sessionManager.state {
        case .idle:     return "Start"
        case .recording: return "Pause"
        case .paused:   return "Resume"
        case .stopping: return "Pause"
        }
    }

    private var primaryButtonIcon: String {
        switch sessionManager.state {
        case .idle:     return "record.circle"
        case .recording: return "pause.fill"
        case .paused:   return "play.fill"
        case .stopping: return "pause.fill"
        }
    }

    private var primaryButtonTint: Color {
        switch sessionManager.state {
        case .idle:     return .accentColor
        case .recording: return .orange
        case .paused:   return .accentColor
        case .stopping: return .orange
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            if sessionManager.state == .recording {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Recording · \(sessionManager.selectedSource.rawValue) · \(formattedElapsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if sessionManager.state == .paused {
                Circle().fill(.yellow).frame(width: 7, height: 7)
                Text("Paused · \(formattedElapsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if sessionManager.state == .stopping {
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .background(.bar)
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let h = sessionManager.elapsedSeconds / 3600
        let m = sessionManager.elapsedSeconds / 60 % 60
        let s = sessionManager.elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func togglePause() {
        Task {
            switch sessionManager.state {
            case .idle:      await sessionManager.start()
            case .recording: await sessionManager.pause()
            case .paused:    await sessionManager.resume()
            case .stopping:  break
            }
        }
    }

    private func endSession() {
        Task { await sessionManager.stop() }
    }

    private func openTranscriptsFolder() {
        let folder = URL(fileURLWithPath: settings.outputFolderPath)
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(folder)
    }
}

// MARK: - Subviews

struct TranscriptRowView: View {
    let entry: TranscriptEntry

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)
            sourceIcon
                .frame(width: 20, alignment: .center)
            frenchText
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text(entry.english.isEmpty ? "…" : entry.english)
                .font(.body)
                .foregroundStyle(entry.english.isEmpty ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Renders each word at its recognition confidence.
    // High (≥0.85): normal • Medium (0.5–0.85): muted • Low (<0.5): grey.
    // Falls back to plain text when no confidence data is available.
    private var frenchText: Text {
        guard !entry.tokens.isEmpty else { return Text(entry.french) }
        return entry.tokens.indices.reduce(Text("")) { acc, i in
            let token = entry.tokens[i]
            let suffix = i < entry.tokens.count - 1 ? " " : ""
            return acc + Text(token.word + suffix).foregroundColor(wordColor(token.confidence))
        }
    }

    private func wordColor(_ confidence: Float) -> Color {
        if confidence >= 0.85 { return .primary }
        if confidence >= 0.5  { return Color.primary.opacity(0.55) }
        return .secondary
    }

    @ViewBuilder
    private var sourceIcon: some View {
        switch entry.source {
        case .mic:
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .system:
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct LiveRowView: View {
    let text: String
    let source: AudioSource?
    @State private var showCursor = true
    @State private var cursorTimer: Timer? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("live")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 38, alignment: .leading)
            sourceIcon
                .frame(width: 20, alignment: .center)
            Text(text + (showCursor ? "▌" : " "))
                .font(.body)
                .foregroundStyle(.primary.opacity(0.5))
        }
        .onAppear {
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
        .onDisappear {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        switch source {
        case .mic:
            Image(systemName: "mic.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        case .system:
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .none:
            Color.clear
        }
    }
}
