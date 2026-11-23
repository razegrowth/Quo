import Foundation
import PDFKit
import UIKit
import Vision

/// A clearer name for a download that arrived with a meaningless one
/// (IMG_2834.pdf, document (3).pdf, scan0001.jpg): its text read on the
/// phone (PDFKit for a PDF with words in it, Vision's text recognition for a
/// scan or a picture), and Apple's model asked for a name from it. Only ever
/// suggested, in the Downloads list, taken with a tap; never renamed on its
/// own. Not offered without Apple Intelligence.
enum FileNames {
    /// Names that say nothing about the file.
    static func messy(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension.lowercased()
        let patterns = [
            "^(img|dsc|dscn|dcim|pxl|photo|image|scan|scanned|doc|document|file|download|untitled|attachment|unnamed|export|print|new)[ _-]?\\(?\\d*\\)?( \\(\\d+\\))?$",
            "^(img|dsc|pxl|scan|doc)[_-]?\\d+.*$",
            "^\\d{5,}$",
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            "^[a-z0-9]{20,}$",
        ]
        return patterns.contains { base.range(of: $0, options: .regularExpression) != nil }
    }

    /// The first words of the file, or nil when it has none to read.
    static func text(of file: URL) async -> String? {
        let ext = file.pathExtension.lowercased()
        if ext == "pdf", let document = PDFDocument(url: file) {
            var words = ""
            for index in 0..<min(document.pageCount, 3) { words += (document.page(at: index)?.string ?? "") + "\n" }
            if words.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 { return String(words.prefix(3_000)) }
            // A scan: its first page, drawn and read.
            if let page = document.page(at: 0) {
                let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
                return await recognise(image.cgImage)
            }
            return nil
        }
        if ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "gif"].contains(ext),
           let image = UIImage(contentsOfFile: file.path) {
            return await recognise(image.cgImage)
        }
        if ["txt", "md", "csv", "rtf", "json", "html", "htm"].contains(ext),
           let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
            return String(decoding: data.prefix(6_000), as: UTF8.self)
        }
        return nil
    }

    /// Vision's text recognition, accurate, on the phone.
    static func recognise(_ image: CGImage?) async -> String? {
        guard let image else { return nil }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            return text.count > 20 ? String(text.prefix(3_000)) : nil
        }.value
    }

    /// A name for the file, its extension kept, or nil.
    static func suggest(for file: URL) async -> String? {
        guard OnDevice.available, messy(file.lastPathComponent), let words = await text(of: file) else { return nil }
        guard let name = await OnDevice.fileName(for: words, current: file.lastPathComponent) else { return nil }
        let ext = file.pathExtension
        return ext.isEmpty ? name : name + "." + ext
    }
}
