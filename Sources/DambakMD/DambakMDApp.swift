import AppKit
import DambakCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class FileOpenDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var pending: [URL] = []
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let model { urls.forEach { model.open($0) } } else { pending.append(contentsOf: urls) }
        sender.reply(toOpenOrPrint: .success)
    }
    func attach(_ model: AppModel) { self.model = model; pending.forEach { model.open($0) }; pending.removeAll() }
}

@main struct DambakMDApp: App {
    @NSApplicationDelegateAdaptor(FileOpenDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("담백 MD", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 520)
                .onAppear { delegate.attach(model); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { model.restoreLastIfNeeded() } }
                .onOpenURL { model.open($0) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Markdown 파일 열기…") { model.chooseFile() }.keyboardShortcut("o")
            }
            CommandMenu("탐색") {
                Button("뒤로") { model.back() }.keyboardShortcut("[", modifiers: .command).disabled(!model.canBack)
                Button("앞으로") { model.forward() }.keyboardShortcut("]", modifiers: .command).disabled(!model.canForward)
                Button("본문 검색") { model.searchOpen = true }.keyboardShortcut("f").disabled(model.currentURL == nil)
            }
            CommandMenu("보기") {
                Button("글자 크게") { model.settings.fontSize = min(26, model.settings.fontSize + 1); model.saveSettings() }.keyboardShortcut("+", modifiers: .command)
                Button("글자 작게") { model.settings.fontSize = max(12, model.settings.fontSize - 1); model.saveSettings() }.keyboardShortcut("-", modifiers: .command)
                Button("기본 글자 크기") { model.settings.fontSize = 16; model.saveSettings() }.keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("목차 표시 전환") { model.settings.showTOC.toggle(); model.saveSettings() }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    @State private var selectedRecentPath: String?
    @State private var isFullScreen = false
    @State private var fullScreenSidebarHidden = false
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.searchOpen { searchBar; Divider() }
            HStack(spacing: 0) {
                if model.showSidebar && !fullScreenSidebarHidden { sidebar.frame(width: 224); Divider() }
                mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.settings.showTOC && model.currentURL != nil { Divider(); toc.frame(width: 222) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
            fullScreenSidebarHidden = isFullScreen
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard model.searchOpen else { return event }
                if event.keyCode == 36 {
                    model.webAction?(.searchStep(event.modifierFlags.contains(.shift) ? -1 : 1))
                    return nil
                }
                if event.keyCode == 53 { model.searchOpen = false; model.searchQuery = ""; return nil }
                return event
            }
        }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
            fullScreenSidebarHidden = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            fullScreenSidebarHidden = false
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { model.open(url) } } }
            return true
        }
        .onChange(of: model.searchOpen) { opened in if opened { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true } } }
        .onChange(of: model.searchQuery) { value in model.webAction?(.search(value)) }
    }
    private var toolbar: some View {
        HStack(spacing: 13) {
            Button {
                if isFullScreen { fullScreenSidebarHidden.toggle() }
                else { model.showSidebar.toggle() }
            } label: { Image(systemName: "sidebar.left") }.help("최근 문서 표시 전환")
            Button { model.back() } label: { Image(systemName: "chevron.left") }.disabled(!model.canBack).help("뒤로")
            Button { model.forward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canForward).help("앞으로")
            Text(model.currentURL?.lastPathComponent ?? "담백 MD").font(.headline).lineLimit(1).frame(maxWidth: .infinity)
            Button { model.chooseFile() } label: { Image(systemName: "folder") }.help("파일 열기")
            Button { model.searchOpen.toggle() } label: { Image(systemName: "magnifyingglass") }.disabled(model.currentURL == nil).help("본문 검색")
            Menu { settingsMenu } label: { Image(systemName: "textformat.size") }.help("보기 설정")
            Button { model.settings.showTOC.toggle(); model.saveSettings() } label: { Image(systemName: "sidebar.right") }.disabled(model.currentURL == nil).help("목차 표시 전환")
        }.buttonStyle(.borderless).padding(.horizontal, 14).frame(height: 46)
    }
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("본문 검색", text: $model.searchQuery).focused($searchFocused).textFieldStyle(.plain)
                .onSubmit { model.webAction?(.searchStep(1)) }
                .onExitCommand { model.searchOpen = false; model.searchQuery = "" }
            Text(model.searchCount == 0 ? "0개" : "\(model.searchIndex)/\(model.searchCount)").foregroundStyle(.secondary).font(.caption)
            Button { model.webAction?(.searchStep(-1)) } label: { Image(systemName: "chevron.up") }.disabled(model.searchCount == 0)
            Button { model.webAction?(.searchStep(1)) } label: { Image(systemName: "chevron.down") }.disabled(model.searchCount == 0)
            Button { model.searchOpen = false; model.searchQuery = "" } label: { Image(systemName: "xmark") }
        }.buttonStyle(.borderless).padding(.horizontal, 18).frame(height: 38)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 문서").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)
            if model.recent.isEmpty { Text("아직 연 문서가 없습니다").foregroundStyle(.secondary).font(.caption).padding(.horizontal, 14) }
            List(selection: $selectedRecentPath) {
                ForEach(model.recent) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: item.path).lastPathComponent).lineLimit(1).font(.body)
                        Text(URL(fileURLWithPath: item.path).deletingLastPathComponent().path).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(item.path)
                    .contextMenu { Button("목록에서 제거") { model.removeRecent(item) } }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedRecentPath) { path in
                if let path, let item = model.recent.first(where: { $0.path == path }) { model.openRecent(item) }
                selectedRecentPath = nil
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    @ViewBuilder private var mainContent: some View {
        if let error = model.error {
            VStack(spacing: 14) { Image(systemName: "exclamationmark.triangle").font(.largeTitle); Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary); Button("다시 선택") { model.selectAccess() } }.padding(36)
        } else if model.currentURL == nil {
            VStack(spacing: 16) { Image(systemName: "doc.text").font(.system(size: 42)).foregroundStyle(.secondary); Text("Markdown 파일을 열거나 여기에 놓으세요").font(.title3); Button("파일 열기") { model.chooseFile() }.buttonStyle(.borderedProminent) }
        } else if model.rendered != nil { ReaderWebView(model: model, isFullScreen: isFullScreen).id(model.currentURL) }
        else { ProgressView("문서 여는 중…") }
    }
    private var toc: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("목차").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 8)
            if model.rendered?.headings.isEmpty != false { Text("이 문서에는 제목이 없습니다").font(.caption).foregroundStyle(.secondary).padding(14) }
            else { ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.rendered?.headings ?? []) { item in
                    TOCRow(item: item, model: model)
                }
            }.padding(.horizontal, 6) } }
            Spacer(minLength: 0)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    @ViewBuilder private var settingsMenu: some View {
        Picker("테마", selection: $model.settings.theme) { Text("시스템").tag("system"); Text("라이트").tag("light"); Text("다크").tag("dark") }.onChange(of: model.settings.theme) { _ in model.saveSettings() }
        Divider()
        Button("글자 크게") { model.settings.fontSize = min(26, model.settings.fontSize + 1); model.saveSettings() }
        Button("글자 작게") { model.settings.fontSize = max(12, model.settings.fontSize - 1); model.saveSettings() }
        Text("글자 크기: \(model.settings.fontSize)px")
        Divider()
        Button("본문 너비 넓게") { model.settings.width = min(1200, model.settings.width + 80); model.saveSettings() }
        Button("본문 너비 좁게") { model.settings.width = max(560, model.settings.width - 80); model.saveSettings() }
        Text("본문 너비: \(model.settings.width)px")
    }
}

private struct TOCRow: View {
    let item: HeadingEntry
    @ObservedObject var model: AppModel
    @State private var isHovered = false

    var body: some View {
        let isActive = model.activeHeading == item.id
        Button { model.selectHeading(item.id) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.accentColor : .clear)
                    .frame(width: 3)
                Text(item.title).lineLimit(2)
            }
            .padding(.leading, CGFloat(item.level - 1) * 11 + 10)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TOCButtonStyle(isActive: isActive, isHovered: isHovered))
        .onHover { isHovered = $0 }
    }
}

private struct TOCButtonStyle: ButtonStyle {
    let isActive: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.28) :
                          isActive ? Color.accentColor.opacity(0.16) :
                          isHovered ? Color.primary.opacity(0.07) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
