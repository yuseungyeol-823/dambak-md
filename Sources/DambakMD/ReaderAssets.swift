import Foundation

enum ReaderAssets {
    static func text(_ name: String, extension fileExtension: String) -> String? {
        let bundleName = "DambakMD_DambakMD.bundle"
        let filename = "\(name).\(fileExtension)"
        let bases = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }

        for base in bases {
            let url = base.appendingPathComponent(bundleName)
                .appendingPathComponent("Resources")
                .appendingPathComponent(filename)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return nil
    }
}
