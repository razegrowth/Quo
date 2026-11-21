import Foundation

// The few Mac types the shared SyncMerge.swift is written against, as the
// iPhone needs them: their stored fields and Codable shapes exactly as the
// Mac's (Spaces.swift, SpaceGradient.swift, Pins.swift, Bookmarks.swift,
// Profiles.swift, Sync.swift), and nothing of their drawing. With these,
// SyncItems.applySpaces, applyPins and applyBookmarks run here unchanged:
// what the iPhone makes of a Mac's record is what another Mac would.

struct Space: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colour: Int
    var icon: String?
    var sharesSignIns: Bool?
    var downloads: String?
    var profile: UUID?
    var gradient: SpaceGradient? = nil
    var strength: SpaceStrength? = nil
    var grain: SpaceGrain? = nil

    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    var isFirst: Bool { id == Space.firstID }
}

struct SpaceGradient: Codable, Equatable, Hashable {
    var colours: [String]
    var angle: Double
    var grain: Bool

    static let defaultAngle: Double = 135

    init(colours: [String], angle: Double = SpaceGradient.defaultAngle, grain: Bool = false) {
        self.colours = colours
        self.angle = angle
        self.grain = grain
    }

    private enum CodingKeys: String, CodingKey { case colours, angle, grain }

    init(from decoder: Decoder) throws {
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        colours = (try? fields?.decodeIfPresent([String].self, forKey: .colours)) ?? []
        angle = (try? fields?.decodeIfPresent(Double.self, forKey: .angle)).flatMap { $0?.isFinite == true ? $0 : nil } ?? Self.defaultAngle
        grain = (try? fields?.decodeIfPresent(Bool.self, forKey: .grain)) ?? false
    }

    /// The colours that read, as "#RRGGBB", at most three.
    var hexes: [String] { Array(colours.filter { HexColour.parse($0) != nil }.prefix(3)) }
    var usable: Bool { !hexes.isEmpty }
}

enum SpaceStrength: String, CaseIterable, Codable, Hashable {
    case subtle, rich, vivid

    init(from decoder: Decoder) throws {
        let text = try? decoder.singleValueContainer().decode(String.self)
        self = text.flatMap(SpaceStrength.init(rawValue:)) ?? .subtle
    }
}

struct SpaceGrain: Codable, Equatable, Hashable {
    let amount: Double

    init(_ amount: Double) {
        self.amount = amount.isFinite ? (min(max(amount, 0), 1) * 100).rounded() / 100 : 0
    }

    init(from decoder: Decoder) throws {
        self.init((try? decoder.singleValueContainer().decode(Double.self)) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var one = encoder.singleValueContainer()
        try one.encode(amount)
    }
}

struct PinDef: Codable, Equatable, Identifiable {
    var id: UUID
    var letter: String
    var home: String
    var title: String
    var name: String?
    var listed: Bool? = nil
    var folder: UUID? = nil
}

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String?
    var children: [Bookmark]?

    var isFolder: Bool { url == nil }
}

struct Profile {
    static let personalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID()
}

/// The keys of the Mac's synced settings: only these count as understood.
enum SyncSettings {
    static let known: Set<String> = [
        "look", "glyph", "search.engine", "search.custom", "search.suggest", "search.keywords", "spaces",
        "pins.list", "pins.home", "tabs.close.after", "tabs.newPlace", "tabs.shortcuts", "shield",
        "privacy.clickIDs", "privacy.gpc", "bookmarks.bar", "quit.confirm",
    ]
}

enum HexColour {
    /// "#RRGGBB" as red, green and blue from 0 to 1.
    static func parse(_ text: String) -> (Double, Double, Double)? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
