import SwiftUI

public struct ContentView: View {
    @StateObject private var store: TranscriptStore
    @StateObject private var sessionManager: SessionManager
    @StateObject private var settings: SettingsStore
    @State private var showingSettings = false

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
    }

    // MARK: - Source picker

    private var sourcePickerBar: some View {
        HStack {
            Text("Source:")
                .foregroundStyle(.secondary)
            Picker("", selection: $sessionManager.selectedSource) {
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
                        LiveRowView(text: store.liveText)
                            .id("live")
                    }
                }
                .padding()
            }
            .onChange(of: store.entries.count) { _ in
                withAnimation {
                    if let lastId = store.entries.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    } else {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.liveText) { _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack {
            Button(action: toggleRecording) {
                Label(
                    sessionManager.state == .recording ? "Stop" : "Start",
                    systemImage: sessionManager.state == .recording ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(sessionManager.state == .recording ? .red : .accentColor)
            .disabled(sessionManager.state == .stopping)

            Spacer()

            Button("Clear") { store.clear() }
                .disabled(sessionManager.state != .idle)

            Button("Open Folder") { openTranscriptsFolder() }

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .disabled(sessionManager.state != .idle)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            if sessionManager.state == .recording {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Recording · \(sessionManager.selectedSource.rawValue) · \(formattedElapsed)")
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

    private func toggleRecording() {
        Task {
            if sessionManager.state == .recording {
                await sessionManager.stop()
            } else {
                await sessionManager.start()
            }
        }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .leading)
                Text(entry.french)
                    .font(.body)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("").frame(width: 38)
                Text("→ \(entry.english)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LiveRowView: View {
    let text: String
    @State private var showCursor = true
    @State private var cursorTimer: Timer? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("live")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 38, alignment: .leading)
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
}
