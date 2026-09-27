import Foundation
import Markdown

public struct HeadingEntry: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let level: Int
}

public struct RenderedPage {
    public let html: String
    public let headings: [HeadingEntry]
}

public enum MarkdownRenderer {
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    public static func safeURL(_ source: String?, image: Bool = false) -> String? {
        guard let source, !source.isEmpty, !source.contains("\\"), !source.contains("\0") else { return nil }
        if source.hasPrefix("#") { return image ? nil : source }
        if let components = URLComponents(string: source), let scheme = components.scheme {
            if image { return nil }
            return ["https", "http", "mailto"].contains(scheme.lowercased()) ? source : nil
        }
        guard !source.hasPrefix("/"), !source.hasPrefix("~"), !source.hasPrefix("//") else { return nil }
        let path = source.split(separator: "?", maxSplits: 1)[0].split(separator: "#", maxSplits: 1)[0]
        if path.split(separator: "/").contains("..") { return nil }
        return source
    }

    public static func render(_ markdown: String) -> RenderedPage {
        let document = Document(parsing: markdown)
        var headings: [HeadingEntry] = []
        var ids: [String: Int] = [:]
        func plain(_ node: Markup) -> String {
            if let text = node as? Markdown.Text { return text.string }
            if let code = node as? InlineCode { return code.code }
            return node.children.map(plain).joined()
        }
        func nodeHTML(_ node: Markup) -> String {
            let children = node.children.map(nodeHTML).joined()
            if node is Document { return children }
            if let heading = node as? Heading {
                let title = plain(node)
                let base = title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "-" }.joined().replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                let slug = base.isEmpty ? "section" : base
                let count = ids[slug, default: 0]
                ids[slug] = count + 1
                let id = count == 0 ? slug : "\(slug)-\(count)"
                headings.append(HeadingEntry(id: id, title: title, level: heading.level))
                return "<h\(heading.level) id=\"\(escape(id))\">\(children)</h\(heading.level)>"
            }
            if node is Paragraph { return "<p>\(children)</p>" }
            if let text = node as? Markdown.Text { return escape(text.string) }
            if node is Emphasis { return "<em>\(children)</em>" }
            if node is Strong { return "<strong>\(children)</strong>" }
            if node is Strikethrough { return "<del>\(children)</del>" }
            if node is SoftBreak { return "\n" }
            if node is LineBreak { return "<br>" }
            if let code = node as? InlineCode { return "<code>\(escape(code.code))</code>" }
            if let code = node as? CodeBlock {
                let language = (code.language ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
                return "<div class=\"code-wrap\"><button class=\"copy\" type=\"button\">복사</button><pre><code class=\"language-\(escape(language))\">\(escape(code.code))</code></pre></div>"
            }
            if node is BlockQuote { return "<blockquote>\(children)</blockquote>" }
            if node is ThematicBreak { return "<hr>" }
            if node is UnorderedList { return "<ul>\(children)</ul>" }
            if let list = node as? OrderedList { return "<ol start=\"\(list.startIndex)\">\(children)</ol>" }
            if let item = node as? ListItem {
                let checkbox: String
                switch item.checkbox {
                case .checked?: checkbox = "<input type=\"checkbox\" checked disabled>"
                case .unchecked?: checkbox = "<input type=\"checkbox\" disabled>"
                case nil: checkbox = ""
                }
                return "<li>\(checkbox)\(children)</li>"
            }
            if node is Table { return "<div class=\"table-wrap\"><table>\(children)</table></div>" }
            if node is Table.Head { return "<thead>\(children)</thead>" }
            if node is Table.Body { return "<tbody>\(children)</tbody>" }
            if node is Table.Row { return "<tr>\(children)</tr>" }
            if let cell = node as? Table.Cell { return "<\(cell.parent is Table.Head ? "th" : "td")>\(children)</\(cell.parent is Table.Head ? "th" : "td")>" }
            if let link = node as? Link {
                guard let url = safeURL(link.destination) else { return children }
                return "<a href=\"\(escape(url))\">\(children)</a>"
            }
            if let image = node as? Image {
                guard let url = safeURL(image.source, image: true) else { return "" }
                return "<img src=\"dambak-resource://image/\(escape(url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))\" alt=\"\(escape(plain(image)))\">"
            }
            if node is HTMLBlock || node is InlineHTML { return "" }
            return children
        }
        let body = nodeHTML(document)
        return RenderedPage(html: body, headings: headings)
    }
}
