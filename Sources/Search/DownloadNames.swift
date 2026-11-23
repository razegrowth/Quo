import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// Tidier downloads: a file that comes in with a name that says nothing,
// "document(3).pdf", "IMG_2041.jpg", "8f3a91c2.pdf", is read on this Mac (a
// PDF's own text, a picture's words by Vision) and Apple's model suggests a
// name that says what it is, "Acme invoice March 2026.pdf". The download's
// card offers it, one click to rename; nothing is ever renamed on its own.
// Settings › Tabs › Suggest names for downloads.
enum DownloadNames {
    static let key = "downloads.names"
    nonisolated(unsafe) static var on = true

    /// A name that says nothing about what the file is.
    static func unclear(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension
        let plain = base.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-_ ]\d+$"#, with: "", options: .regularExpression)
        let lower = plain.lowercased()
        let vague: Set<String> = ["document", "download", "file", "untitled", "image", "photo", "scan", "scanned",
                                  "invoice", "receipt", "attachment", "doc", "pdf", "img", "dsc", "pxl", "screenshot",
                                  "export", "report", "print", "statement", "unknown", "new", "temp", "tmp", "page"]
        if vague.contains(lower) { return true }
        if base.range(of: #"^(IMG|DSC|DSCN|PXL|MVIMG|Screenshot|Scan|CamScanner|WhatsApp Image)[-_ ]"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // A code: a run of digits or hex, a UUID.
        if base.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-"#, options: .regularExpression) != nil { return true }
        if base.range(of: #"^[0-9a-fA-F_\-]{8,}$"#, options: .regularExpression) != nil { return true }
        let letters = base.filter(\.isLetter).count
        if base.count <= 3 || Double(letters) < Double(base.count) * 0.45 { return true }
        return false
    }

    /// The words in the file, read on this Mac: a PDF's first pages, a
    /// picture's text, a text file's start. Nil for anything else.
    static func text(of file: URL) async -> String? {
        guard let type = UTType(filenameExtension: file.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: file) else { return nil }
            var text = ""
            for index in 0..<min(document.pageCount, 3) { text += (document.page(at: index)?.string ?? "") + "\n" }
            return String(text.prefix(4_000))
        }
        if type.conforms(to: .image) {
            return await Task.detached(priority: .utility) { () -> String? in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: file)
                guard (try? handler.perform([request])) != nil else { return nil }
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return String(lines.joined(separator: "\n").prefix(4_000))
            }.value
        }
        if type.conforms(to: .plainText) || type.conforms(to: .commaSeparatedText) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 4_000)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }

    /// A clearer name for the file, its own extension kept, or nil: its name
    /// is clear already, there's nothing in it to read, or no model here.
    @MainActor
    static func suggest(for file: URL) async -> String? {
        guard on, unclear(file.lastPathComponent) else { return nil }
        guard let text = await text(of: file)?.trimmingCharacters(in: .whitespacesAndNewlines), text.count >= 30 else { return nil }
        if Store.testing, let canned { return finish(canned(text), for: file) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *), OnDevice.available {
            let session = LanguageModelSession(instructions: """
                You name a downloaded file so a person can find it later in their Downloads folder. Answer with the \
                name alone: three to seven words, no file extension, no quotes. Say what kind of document it is, who \
                it's from or about, and its date or number if it has one, like "Acme invoice March 2026", \
                "Lisbon flight booking TAP 14 May" or "Lease agreement 12 Rua Augusta".
                """)
            let prompt = "Its name now: \(file.lastPathComponent)\n\nWhat it says:\n\(text.prefix(3_000))"
            do {
                let answer = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
                lastSaid = answer.content
                return finish(answer.content, for: file)
            } catch {
                lastSaid = "error: \(error)"
                return nil
            }
        }
        #endif
        return nil
    }

    /// The model's words made a file name: one line, nothing a folder can't
    /// hold, not too long, the file's own extension after it.
    static func finish(_ said: String, for file: URL) -> String? {
        var name = said.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        name = name.replacingOccurrences(of: #"[/\\:*?"<>|]"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*.").union(.whitespaces))
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        let ext = file.pathExtension
        if !ext.isEmpty, name.lowercased().hasSuffix("." + ext.lowercased()) { name = String(name.dropLast(ext.count + 1)) }
        guard name.count >= 3, name.split(separator: " ").count <= 10 else { return nil }
        name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces)
        let full = ext.isEmpty ? name : name + "." + ext
        return full == file.lastPathComponent ? nil : full
    }

    /// Renamed beside where it is, with " 2" and on if the name is taken.
    static func rename(_ file: URL, to name: String) -> URL? {
        let folder = file.deletingLastPathComponent()
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        guard (try? FileManager.default.moveItem(at: file, to: target)) != nil else { return nil }
        return target
    }

    /// What the model last said, for the bench.
    @MainActor static var lastSaid: String?

    /// A test run's stand-in for the model (bench dlname).
    @MainActor static var canned: ((String) -> String)?
}
