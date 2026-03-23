import Foundation

enum TextFileLoader {

    static func readText(from url: URL) throws -> String {
        try loadText(from: url).text
    }

    static func loadText(from url: URL) throws -> (text: String, fileSize: Int?) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let data = try Data(contentsOf: url)

        if let string = String(data: data, encoding: .utf8) {
            return (string, values?.fileSize)
        }
        if let string = String(data: data, encoding: .ascii) {
            return (string, values?.fileSize)
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
