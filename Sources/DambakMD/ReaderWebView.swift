import DambakCore
import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ReaderWebView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    let isFullScreen: Bool
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let script = (try? String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!, encoding: .utf8)) ?? ""
        let highlight = (try? String(contentsOf: Bundle.module.url(forResource: "highlight.min", withExtension: "js", subdirectory: "Resources")!, encoding: .utf8)) ?? ""
        config.userContentController.addUserScript(WKUserScript(source: highlight + "\n" + script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "reader")
        config.setURLSchemeHandler(context.coordinator.imageHandler, forURLScheme: "dambak-resource")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        context.coordinator.isFullScreen = isFullScreen
        model.webAction = { [weak coordinator = context.coordinator] action in coordinator?.perform(action) }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.isFullScreen != isFullScreen {
            context.coordinator.isFullScreen = isFullScreen
            context.coordinator.perform(.fullscreen(isFullScreen))
        }
        context.coordinator.imageHandler.base = model.currentURL?.deletingLastPathComponent()
        if context.coordinator.loadedID != model.navigationID, let page = model.rendered {
            context.coordinator.loadedID = model.navigationID
            let css = (try? String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "css", subdirectory: "Resources")!, encoding: .utf8)) ?? ""
            let html = """
            <!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src dambak-resource: data:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; form-action 'none'"><style>\(css)</style></head><body><main>\(page.html)</main></body></html>
            """
            web.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        }
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var loadedID: UUID?
        var isFullScreen = false
        let model: AppModel
        let imageHandler = ImageHandler()
        init(model: AppModel) { self.model = model }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                perform(.settings(model.settings)); perform(.fullscreen(isFullScreen)); perform(.restore(model.targetPosition)); model.targetPosition = nil
                if !model.searchQuery.isEmpty { perform(.search(model.searchQuery)) }
            case "link": model.resolveLink(body["value"] as? String ?? "")
            case "heading": model.reportActiveHeading(body["value"] as? String ?? "")
            case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(body["value"] as? String ?? "", forType: .string)
            case "search": if let value = body["value"] as? [String: Int] { model.searchCount = value["count"] ?? 0; model.searchIndex = value["index"] ?? 0 }
            case "position": if let value = body["value"] as? [String: Any] { model.updatePosition(ReadingPosition(heading: value["heading"] as? String ?? "", fraction: value["fraction"] as? Double ?? 0, y: value["y"] as? Double ?? 0)) }
            default: break
            }
        }
        func perform(_ action: WebAction) {
            guard let web else { return }
            let function: String; let arguments: [String: Any]
            switch action {
            case .settings(let settings): function = "applySettings(settings)"; arguments = ["settings": ["theme":settings.theme,"fontSize":settings.fontSize,"width":settings.width]]
            case .heading(let id): function = "goTo(id)"; arguments = ["id":id.removingPercentEncoding ?? id]
            case .search(let query): function = "search(query)"; arguments = ["query":query]
            case .searchStep(let direction): function = "stepSearch(direction)"; arguments = ["direction":direction]
            case .restore(let position): function = "restorePosition(pos)"; arguments = ["pos": position.map { ["heading":$0.heading,"fraction":$0.fraction,"y":$0.y] } ?? NSNull()]
            case .fullscreen(let enabled): function = "setFullscreen(enabled)"; arguments = ["enabled":enabled]
            }
            web.callAsyncJavaScript(function, arguments: arguments, in: nil, in: .page) { _ in }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel); model.resolveLink(url.absoluteString); return
            }
            if navigationAction.request.url?.scheme == "about" { decisionHandler(.allow) } else { decisionHandler(.cancel) }
        }
    }
}

final class ImageHandler: NSObject, WKURLSchemeHandler {
    var base: URL?
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let base, let url = task.request.url, url.host == "image",
              let encoded = url.path.dropFirst().removingPercentEncoding,
              let safe = MarkdownRenderer.safeURL(encoded, image: true) else { task.didFailWithError(NSError(domain: "DambakMD", code: 2)); return }
        let file = base.appendingPathComponent(safe).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path + "/"),
              ["png", "jpg", "jpeg", "gif", "webp"].contains(file.pathExtension.lowercased()),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000,
              let data = try? Data(contentsOf: file) else { task.didFailWithError(NSError(domain: "DambakMD", code: 3)); return }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
