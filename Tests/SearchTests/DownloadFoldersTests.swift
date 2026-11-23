import XCTest
@testable import Search

final class DownloadFoldersTests: XCTestCase {
    func testFolders() {
        XCTAssertEqual(Browser.downloadFolders("a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("photos/2026/a.jpg"), ["photos", "2026"])
        XCTAssertEqual(Browser.downloadFolders("/etc/a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("../a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("x/../../a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("x//a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("~/a.jpg"), [])
        XCTAssertEqual(Browser.downloadFolders("./a.jpg"), [])
    }

    /// A download dragged out carries its own file URL, as a drag out of
    /// Finder does, so a page's upload box takes the file itself.
    func testADraggedDownloadIsItsFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dragged-\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = Loot.dragged(file)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("public.file-url"), provider.registeredTypeIdentifiers.description)
        XCTAssertEqual(provider.suggestedName, file.lastPathComponent)
        let loaded = expectation(description: "the URL")
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            XCTAssertEqual((object as? URL)?.standardizedFileURL, file.standardizedFileURL)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
    }

    /// A file you told the save panel to replace is moved out of the way
    /// first: WebKit never writes over one, and the download sat at nothing.
    @MainActor func testReplacingMovesTheOldFileToTheBin() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replacing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fresh = folder.appendingPathComponent("new.pdf")
        XCTAssertEqual(Browser.replacing(fresh), fresh, "nothing there: the same file")

        let name = "quo-replacing-test-\(UUID().uuidString).pdf"
        let there = folder.appendingPathComponent(name)
        try Data("old".utf8).write(to: there)
        XCTAssertEqual(Browser.replacing(there), there, "the same name, for the download")
        XCTAssertFalse(FileManager.default.fileExists(atPath: there.path), "and the old one gone from the folder")
        // Out of the Bin again, so the test leaves nothing behind.
        let bin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for item in (try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? [] where item.hasPrefix(name.replacingOccurrences(of: ".pdf", with: "")) {
            try? FileManager.default.removeItem(at: bin.appendingPathComponent(item))
        }
    }
}
