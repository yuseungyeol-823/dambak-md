import DambakCore
import AppKit
import Combine
import Foundation

struct ReadingPosition: Codable, Equatable {
    var heading: String = ""
    var fraction: Double = 0
    var y: Double = 0
}
struct RecentDocument: Codable, Identifiable {
    var id: String { path }
    let path: String
    let bookmark: Data?
    var position: ReadingPosition?
}
struct ReadingSettings: Codable {
    var theme = "system"
    var fontSize = 16
    var width = 800
    var showTOC = true
}

@MainActor final class AppModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var rendered: RenderedPage?
    @Published var error: String?
    @Published var recent: [RecentDocument] = []
    @Published var settings = ReadingSettings()
    @Published var activeHeading = ""
    @Published var searchOpen = false
    @Published var searchQuery = ""
    @Published var searchCount = 0
    @Published var searchIndex = 0
    @Published var showSidebar = true
    @Published var navigationID = UUID()
    var targetPosition: ReadingPosition?
    var webAction: ((WebAction) -> Void)?
    private var history: [(URL, ReadingPosition?)] = []
    private var historyIndex = -1
    private var currentPosition: ReadingPosition?
    private var scopeURL: URL?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var loadingVersion = UUID()
    private let defaults = UserDefaults.standard
    var canBack: Bool { historyIndex > 0 }
    var canForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    init() {
        if let data = defaults.data(forKey: "settings"), let value = try? JSONDecoder().decode(ReadingSettings.self, from: data) { settings = value }
        if let data = defaults.data(forKey: "recent"), let value = try? JSONDecoder().decode([RecentDocument].self, from: data) { recent = value }

    }
    func restoreLastIfNeeded() {
        guard currentURL == nil, let path = defaults.string(forKey: "lastDocument"), let item = recent.first(where: { $0.path == path }) else { return }
        openRecent(item)
    }
    func saveSettings() { if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings") }; webAction?(.settings(settings)) }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func openRecent(_ item: RecentDocument) {
        var stale = false
        if let bookmark = item.bookmark, let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
            open(url, restore: item.position)
        } else { open(URL(fileURLWithPath: item.path), restore: item.position) }
    }
    func removeRecent(_ item: RecentDocument) { recent.removeAll {$0.path == item.path}; persistRecent() }
    func open(_ url: URL, restore: ReadingPosition? = nil, recordHistory: Bool = true) {
        let resolved = url.standardizedFileURL
        guard ["md", "markdown"].contains(resolved.pathExtension.lowercased()) else { error = "Markdown 파일(.md, .markdown)을 선택해 주세요."; return }
        if recordHistory, let currentURL, historyIndex >= 0 { history[historyIndex].1 = currentPosition; updateRecentPosition(currentURL, currentPosition) }
        stopWatching()
        if let scopeURL { scopeURL.stopAccessingSecurityScopedResource() }
        scopeURL = resolved
        _ = resolved.startAccessingSecurityScopedResource()
        currentURL = resolved
        rendered = nil
        error = nil
        targetPosition = restore
        currentPosition = restore
        if recordHistory {
            history = Array(history.prefix(historyIndex + 1))
            history.append((resolved, restore)); historyIndex = history.count - 1
        }
        let bookmark = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        recent.removeAll { $0.path == resolved.path }
        recent.insert(RecentDocument(path: resolved.path, bookmark: bookmark, position: restore), at: 0)
        recent = Array(recent.prefix(20))
        persistRecent()
        defaults.set(resolved.path, forKey: "lastDocument")
        reload()
        startWatching()
    }
    func reload() {
        guard let url = currentURL else { return }
        let version = UUID(); loadingVersion = version
        let previous = currentPosition
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let bytes = attributes[.size] as? NSNumber, bytes.intValue > 12_000_000 { throw NSError(domain: "DambakMD", code: 1, userInfo: [NSLocalizedDescriptionKey:"12MB를 넘는 문서는 현재 버전에서 열 수 없습니다."]) }
                let text = try String(contentsOf: url, encoding: .utf8)
                let result = MarkdownRenderer.render(text)
                DispatchQueue.main.async {
                    guard self.loadingVersion == version else { return }
                    self.error = nil; self.rendered = result
                    self.targetPosition = previous ?? self.targetPosition
                    self.navigationID = UUID()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.loadingVersion == version else { return }
                    self.error = FileManager.default.fileExists(atPath: url.path) ? "파일을 읽을 수 없습니다. 접근 권한이나 UTF-8 인코딩을 확인해 주세요.\n\(error.localizedDescription)" : "파일이 이동되었거나 삭제되었습니다. 다시 선택해 주세요."
                }
            }
        }
    }
    func back() { guard canBack else { return }; history[historyIndex].1 = currentPosition; historyIndex -= 1; let target = history[historyIndex]; open(target.0, restore: target.1, recordHistory: false) }
    func forward() { guard canForward else { return }; history[historyIndex].1 = currentPosition; historyIndex += 1; let target = history[historyIndex]; open(target.0, restore: target.1, recordHistory: false) }
    func updatePosition(_ pos: ReadingPosition) { currentPosition = pos; if let url = currentURL { updateRecentPosition(url, pos) } }
    private func updateRecentPosition(_ url: URL, _ pos: ReadingPosition?) { guard let index = recent.firstIndex(where: {$0.path == url.path}) else { return }; recent[index].position = pos; persistRecent() }
    private func persistRecent() { if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: "recent") } }
    func resolveLink(_ href: String) {
        guard let base = currentURL, let safe = MarkdownRenderer.safeURL(href) else { return }
        if safe.hasPrefix("#") { webAction?(.heading(String(safe.dropFirst()))); return }
        if let url = URL(string: safe), let scheme = url.scheme {
            if ["http", "https"].contains(scheme.lowercased()) { NSWorkspace.shared.open(url) }
            else if scheme == "mailto" { NSWorkspace.shared.open(url) }
            return
        }
        let path = safe.components(separatedBy: "#")[0].removingPercentEncoding ?? safe
        let target = base.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
        guard ["md", "markdown"].contains(target.pathExtension.lowercased()) else { return }
        open(target)
        if let anchor = safe.split(separator: "#", maxSplits: 1).dropFirst().first { webAction?(.heading(String(anchor))) }
    }
    func selectAccess() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = "문서 또는 필요한 파일이 있는 폴더를 선택해 접근 권한을 허용해 주세요."
        if panel.runModal() == .OK, let url = panel.url { if url.hasDirectoryPath { reload() } else { open(url) } }
    }
    private func startWatching() {
        guard let dir = currentURL?.deletingLastPathComponent() else { return }
        let fd = Darwin.open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in self?.watchFile(); self?.scheduleReload() }
            source.setCancelHandler { Darwin.close(fd) }
            source.resume(); directoryWatcher = source
        }
        watchFile()
    }
    private func watchFile() {
        fileWatcher?.cancel(); fileWatcher = nil
        guard let url = currentURL else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume(); fileWatcher = source
    }
    private func scheduleReload() { debounce?.cancel(); let task = DispatchWorkItem { [weak self] in self?.reload() }; debounce = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task) }
    private func stopWatching() { debounce?.cancel(); debounce = nil; directoryWatcher?.cancel(); directoryWatcher = nil; fileWatcher?.cancel(); fileWatcher = nil }

}

enum WebAction { case settings(ReadingSettings), heading(String), search(String), searchStep(Int), restore(ReadingPosition?) }
