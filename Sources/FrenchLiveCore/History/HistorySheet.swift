import SwiftUI

struct HistorySheet: View {
    let folderPath: String
    @State private var files: [URL] = []
    @State private var selectedFile: URL? = nil
    @State private var content: String = ""

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f
    }()

    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy · HH:mm"
        return f
    }()

    var body: some View {
        HSplitView {
            fileList
            contentPane
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }
                .disabled(selectedFile == nil)
            }
        }
        .onAppear { loadFiles() }
        .onChange(of: selectedFile) { url in
            loadContent(url)
        }
    }

    private var fileList: some View {
        List(files, id: \.self, selection: $selectedFile) { url in
            Text(displayName(for: url))
                .contextMenu {
                    Button("Move to Trash", role: .destructive) {
                        deleteFile(url)
                    }
                }
        }
        .frame(minWidth: 200)
        .onDeleteCommand {
            if let url = selectedFile { deleteFile(url) }
        }
        .overlay {
            if files.isEmpty {
                Text("No transcripts yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contentPane: some View {
        ScrollView {
            if selectedFile != nil {
                Text(content)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("Select a transcript.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 300)
    }

    private func loadFiles() {
        let folderURL = URL(fileURLWithPath: folderPath)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ) else {
            files = []
            return
        }
        files = urls
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func loadContent(_ url: URL?) {
        guard let url else { content = ""; return }
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Could not load file."
    }

    private func deleteFile(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        files.removeAll { $0 == url }
        if selectedFile == url {
            selectedFile = nil
            content = ""
        }
    }

    private func displayName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if let date = Self.inputFormatter.date(from: stem) {
            return Self.outputFormatter.string(from: date)
        }
        return stem
    }
}
