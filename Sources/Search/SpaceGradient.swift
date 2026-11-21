import SwiftUI
import AppKit

// A space's look of its own: one, two or three colours picked on a wheel,
// the way Arc themes a space. Only for whoever wants one (the space's menu
// › Colour…, see SpaceLookPicker below): a space without one is washed with
// its colour, or nothing, exactly as before, and reads and writes
// spaces.json as it always did. Removing it gives the space back its colour.
//
// Two or three colours make a gradient; one is a colour of its own, off the
// wheel rather than one of Spaces.colours. A Search from before one-colour
// looks reads that as no gradient, and keeps the space's colour.
//
// The gradient takes the colour's place wherever the wash is drawn — the
// column or the strip, the bookmarks bar, the ground around the page's
// card — at the same strength (Spaces.washLight, washDark). It runs across
// the window, not across each of those on its own, so where the column
// meets the ground the colours carry on.
//
// The colours are mixed in OKLab, keeping the chroma of the ends, so the
// middle of blue to orange is as bright and as coloured as they are rather
// than a grey. Each colour's lightness is held to the band the plain
// colours sit in: whatever is picked, the wash moves the ground no further
// than they do, and the greys of the live tab and the one under the
// pointer keep their step from it.
//
// Drawn once, as a gradient of stops; nothing moves while it stays, and a
// change crossfades once, as the colour's does. The grain is one small
// tile of noise, made once and laid over it at the space's amount.

struct SpaceGradient: Codable, Equatable, Hashable {
    /// The colours in the order they run, "#RRGGBB" in sRGB: one to three.
    var colours: [String]
    /// The way it runs, in degrees as CSS has them: 0 up, 90 right, 180 down.
    var angle: Double
    /// Whether there is grain over it. The amount is the space's own
    /// (Space.grain); this stays for a Search from before amounts, which
    /// reads it, and a gradient from one with it on and no amount has
    /// Grain.legacy.
    var grain: Bool

    static let defaultAngle: Double = 135
    static let most = 3

    init(colours: [String], angle: Double = SpaceGradient.defaultAngle, grain: Bool = false) {
        self.colours = colours
        self.angle = angle
        self.grain = grain
    }

    private enum CodingKeys: String, CodingKey { case colours, angle, grain }

    /// Never fails: a gradient that doesn't read is no gradient (see
    /// `usable`), and the space keeps its colour. Failing here would fail
    /// the whole list of spaces.
    init(from decoder: Decoder) throws {
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        colours = (try? fields?.decodeIfPresent([String].self, forKey: .colours)) ?? []
        angle = (try? fields?.decodeIfPresent(Double.self, forKey: .angle)).flatMap { $0?.isFinite == true ? $0 : nil } ?? Self.defaultAngle
        grain = (try? fields?.decodeIfPresent(Bool.self, forKey: .grain)) ?? false
    }

    /// The colours as drawn: the first three that read, each held to the
    /// wash's band of lightness and chroma.
    var drawn: [OKLab] {
        Array(colours.compactMap(OKLab.init(hex:)).prefix(Self.most)).map(\.held)
    }

    /// A colour or more that reads; otherwise the space's colour stands.
    var usable: Bool { !drawn.isEmpty }

    /// One colour: a colour of its own rather than a gradient.
    var single: Bool { drawn.count == 1 }

    /// What the gradient is drawn with: its colours mixed in OKLab at
    /// `count` stops, evenly spaced. SwiftUI blends between neighbours,
    /// which are close enough that how it blends doesn't show. One colour
    /// is the same at every stop.
    func stops(count: Int = 24, strength: SpaceStrength = .subtle, dark: Bool = false) -> [Gradient.Stop] {
        let lab = drawn.map { strength.tone($0, dark: dark) }
        guard !lab.isEmpty else { return [] }
        let count = lab.count == 1 ? 2 : count
        return (0..<count).map { step in
            let t = Double(step) / Double(count - 1)
            let (r, g, b) = OKLab.along(lab, at: t).srgb
            return Gradient.Stop(color: Color(.sRGB, red: r, green: g, blue: b), location: t)
        }
    }

    /// Its first colour as drawn: for the space's dot and its menu.
    var lead: Color? {
        drawn.first.map { lab in let (r, g, b) = lab.srgb; return Color(.sRGB, red: r, green: g, blue: b) }
    }

    /// Where it starts and ends, as unit points of a box at `frame` in a
    /// window `room` big: the line through the window's middle at `angle`,
    /// long enough that the window's corners lie on its ends, as in CSS.
    /// The column, the bars and the ground then each show their part of
    /// one gradient. No room (drawn off screen) is the box alone.
    func points(frame: CGRect, room: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        let box = room.width > 0 && room.height > 0 ? CGRect(origin: .zero, size: room) : CGRect(origin: frame.origin, size: frame.size)
        let radians = angle * .pi / 180
        let dx = sin(radians), dy = -cos(radians)
        let length = abs(box.width * dx) + abs(box.height * dy)
        let mid = CGPoint(x: box.midX, y: box.midY)
        let start = CGPoint(x: mid.x - dx * length / 2, y: mid.y - dy * length / 2)
        let end = CGPoint(x: mid.x + dx * length / 2, y: mid.y + dy * length / 2)
        func unit(_ p: CGPoint) -> UnitPoint {
            UnitPoint(x: frame.width > 0 ? (p.x - frame.minX) / frame.width : 0,
                      y: frame.height > 0 ? (p.y - frame.minY) / frame.height : 0)
        }
        return (unit(start), unit(end))
    }

    // MARK: - choices

    /// Twelve hues at one lightness and chroma, so each washes as strongly
    /// as the next, and two quiet ones: what the ready-made gradients are
    /// made of, and where the wheel's handles snap.
    static let swatches: [(name: String, hex: String)] = {
        let hues: [(String, Double)] = [
            ("Red", 25), ("Orange", 55), ("Amber", 85), ("Lime", 125), ("Green", 150), ("Teal", 185), ("Cyan", 215),
            ("Blue", 250), ("Indigo", 275), ("Violet", 300), ("Magenta", 330), ("Pink", 355),
        ]
        return hues.map { ($0.0, OKLab(lightness: 0.70, chroma: 0.14, hue: $0.1).hex) }
            + [("Graphite", OKLab(lightness: 0.62, chroma: 0.015, hue: 260).hex),
               ("Sand", OKLab(lightness: 0.78, chroma: 0.045, hue: 75).hex)]
    }()

    static func swatch(_ name: String) -> String { swatches.first { $0.name == name }?.hex ?? "#808080" }

    static let presets: [(name: String, gradient: SpaceGradient)] = [
        ("Sunrise", SpaceGradient(colours: [swatch("Amber"), swatch("Pink")])),
        ("Lagoon", SpaceGradient(colours: [swatch("Teal"), swatch("Blue")])),
        ("Orchard", SpaceGradient(colours: [swatch("Lime"), swatch("Teal")])),
        ("Dusk", SpaceGradient(colours: [swatch("Indigo"), swatch("Magenta"), swatch("Orange")])),
        ("Glacier", SpaceGradient(colours: [swatch("Cyan"), swatch("Indigo")])),
        ("Ember", SpaceGradient(colours: [swatch("Red"), swatch("Amber")])),
    ]

    /// A first gradient for a space: its colour, if it has one, into the
    /// hue beside it; Lagoon otherwise.
    static func starting(from colour: Int) -> SpaceGradient {
        let from = ["", "Blue", "Green", "Orange", "Red", "Violet"]
        let to = ["", "Violet", "Teal", "Pink", "Amber", "Pink"]
        guard from.indices.contains(colour), colour > 0 else { return presets[1].gradient }
        return SpaceGradient(colours: [swatch(from[colour]), swatch(to[colour])])
    }
}

/// How strongly a space's colour or gradient washes the chrome. Subtle is
/// the faint wash every space had; Rich and Vivid are for whoever wants the
/// colour seen, closer to Arc's saturated themes (the Colour… picker's
/// Strength). Nil in spaces.json is Subtle, so a list from before reads
/// and writes as it did.
///
/// Stronger, the wash stays on its side of the window's appearance: in a
/// light window a deeper tint the ink still reads on, in a dark one a deep
/// colour the light ink reads on. So the column's ink never has to turn
/// over; the colour's lightness is held further for that (`tone`), and the
/// greys and the tab titles are black or white with alpha (see Greys),
/// keeping their step from whatever ground they land on. Checked against
/// the worst colours in SpaceGradientTests.
enum SpaceStrength: String, CaseIterable, Codable, Hashable {
    case subtle, rich, vivid

    var name: String {
        switch self {
        case .subtle: return "Subtle"
        case .rich: return "Rich"
        case .vivid: return "Vivid"
        }
    }

    /// Never fails: a strength a newer Search writes, or one that doesn't
    /// read, is Subtle. Failing here would fail the whole list of spaces.
    init(from decoder: Decoder) throws {
        let text = try? decoder.singleValueContainer().decode(String.self)
        self = text.flatMap(SpaceStrength.init(rawValue:)) ?? .subtle
    }

    /// How much of the colour the chrome wears. Subtle is the colour's
    /// wash as it always was (Spaces.washLight, washDark).
    func opacity(dark: Bool) -> Double {
        switch self {
        case .subtle: return dark ? Spaces.washDark : Spaces.washLight
        case .rich: return dark ? 0.22 : 0.18
        case .vivid: return dark ? 0.40 : 0.30
        }
    }

    /// The colour as this strength washes with it: more chroma, and its
    /// lightness held so the washed ground stays light in a light window
    /// (Vivid: no darker than 0.62) and deep in a dark one (Rich: no
    /// lighter than 0.72, Vivid: 0.48 to 0.58). Subtle is the colour as held.
    func tone(_ colour: OKLab, dark: Bool) -> OKLab {
        let (boost, band): (Double, ClosedRange<Double>) = {
            switch self {
            case .subtle: return (1, 0...1)
            case .rich: return (1.15, dark ? 0...0.72 : 0...1)
            case .vivid: return (1.3, dark ? 0.48...0.58 : 0.62...1)
            }
        }()
        // No more chroma than the band allows a colour, however strong: a
        // blue already near it would otherwise wash the column royal blue.
        let chroma = colour.chroma, wanted = min(chroma * boost, max(chroma, OKLab.mostChroma))
        let scale = chroma > 1e-9 ? wanted / chroma : 1
        return OKLab(L: min(max(colour.L, band.lowerBound), band.upperBound), a: colour.a * scale, b: colour.b * scale)
    }

    /// How much of the grain's tile shows for `amount` of grain (0 to 1),
    /// a touch more on a stronger colour, or it is lost in it.
    func grain(_ amount: Double, dark: Bool) -> Double {
        // Counted from the old switch's, so a space from then is exactly as it was.
        let base = dark ? Grain.dark : Grain.light
        let boost: Double = {
            switch self {
            case .subtle: return 1
            case .rich: return 1.25
            case .vivid: return 1.5
            }
        }()
        return base * (Grain.felt(amount) / Grain.legacy) * boost
    }

    /// The grain a gradient from before amounts had, switched on.
    func grain(dark: Bool) -> Double { grain(Grain.legacy, dark: dark) }
}

/// How much grain lies over a space's wash, 0 to 1. Kept as a plain number
/// in spaces.json, and never fails to read: one that doesn't is none, and
/// one out of bounds is held to them. Failing here would fail the whole
/// list of spaces.
struct SpaceGrain: Codable, Equatable, Hashable {
    let amount: Double

    /// Held to 0…1, in hundredths: as fine as the slider goes, and what
    /// is written is then exactly what is read back.
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

extension Space {
    /// How strongly it washes the chrome: Subtle unless chosen.
    var washStrength: SpaceStrength { strength ?? .subtle }

    /// How much grain lies over its wash: its own amount, or a gradient's
    /// from before amounts, or none.
    var grainAmount: Double {
        if let grain { return grain.amount }
        return gradient?.usable == true && gradient?.grain == true ? Grain.legacy : 0
    }
}

/// What a space washes the chrome with: one of Spaces.colours, or its
/// gradient (one colour of its own included). Nil is nothing at all, the
/// look every space had before.
enum SpaceLook: Equatable {
    case colour(Int)
    case gradient(SpaceGradient)
}

extension Space {
    var look: SpaceLook? {
        if let gradient, gradient.usable { return .gradient(gradient) }
        return colour > 0 && Spaces.colours.indices.contains(colour) ? .colour(colour) : nil
    }
}

// MARK: - OKLab

/// A colour in Björn Ottosson's OKLab: L from black (0) to white (1), a and
/// b its two opponent axes. Even steps in it look even, which sRGB's don't.
struct OKLab: Equatable {
    var L: Double
    var a: Double
    var b: Double

    init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    init(lightness: Double, chroma: Double, hue degrees: Double) {
        let h = degrees * .pi / 180
        self.init(L: lightness, a: chroma * cos(h), b: chroma * sin(h))
    }

    init(r: Double, g: Double, b blue: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (linear(r), linear(g), linear(blue))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255)
    }

    var chroma: Double { (a * a + b * b).squareRoot() }

    /// Its hue in degrees, 0 to 360: 0 along +a, a pinkish red.
    var hue: Double {
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Linear sRGB, unclamped: outside 0…1 is outside what sRGB can show.
    var linear: (Double, Double, Double) {
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// Whether sRGB can show it as it is.
    var fits: Bool {
        let (r, g, b) = linear
        let e = 1e-6
        return r >= -e && r <= 1 + e && g >= -e && g <= 1 + e && b >= -e && b <= 1 + e
    }

    /// Gamma-encoded sRGB, 0…1. A colour sRGB can't show keeps its
    /// lightness and hue and loses only as much chroma as it must.
    var srgb: (Double, Double, Double) {
        var colour = self
        if !fits {
            var low = 0.0, high = 1.0
            for _ in 0..<16 {
                let mid = (low + high) / 2
                if OKLab(L: L, a: a * mid, b: b * mid).fits { low = mid } else { high = mid }
            }
            colour = OKLab(L: L, a: a * low, b: b * low)
        }
        func encode(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        let (r, g, b) = colour.linear
        return (encode(r), encode(g), encode(b))
    }

    var hex: String {
        let (r, g, b) = srgb
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// The band a wash colour is held to: the plain colours' own, about
    /// 0.6 to 0.8. A near-black or near-white washed at their strength
    /// would move the ground as far as the grey of the live tab is from it.
    static let lightnessBand = 0.56...0.80
    static let mostChroma = 0.20

    var held: OKLab {
        let lightness = min(max(L, Self.lightnessBand.lowerBound), Self.lightnessBand.upperBound)
        let scale = chroma > Self.mostChroma ? Self.mostChroma / chroma : 1
        return OKLab(L: lightness, a: a * scale, b: b * scale)
    }

    /// Between `self` and `other` at t: straight across OKLab for the hue,
    /// with the chroma going evenly from one end's to the other's, so the
    /// middle is no greyer than the ends.
    func mix(_ other: OKLab, _ t: Double) -> OKLab {
        var out = OKLab(L: L + (other.L - L) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
        let wanted = chroma + (other.chroma - chroma) * t
        let has = out.chroma
        if has > 1e-4 { out.a *= wanted / has; out.b *= wanted / has }
        return out
    }

    /// Along a run of colours, evenly spaced, at t in 0…1.
    static func along(_ colours: [OKLab], at t: Double) -> OKLab {
        guard colours.count > 1 else { return colours.first ?? OKLab(L: 0.7, a: 0, b: 0) }
        let spot = min(max(t, 0), 1) * Double(colours.count - 1)
        let at = min(Int(spot), colours.count - 2)
        return colours[at].mix(colours[at + 1], spot - Double(at))
    }
}

// MARK: - the wheel

/// The Colour… picker's wheel: hue round it, chroma from the grey middle
/// out to the most sRGB shows of that hue at the rim, every colour at one
/// lightness, the middle of the band the wash holds colours to (OKLab.held),
/// so what is picked is what washes. Warm hues sit at the top right, cool
/// ones at the bottom left.
///
/// Points on it are as on screen: the middle at 0, the rim at 1, y down.
enum ColourWheel {
    static let lightness = 0.70
    /// Turns the hues so OKLab's red (25°) is at the top.
    private static let turn = 115.0

    /// The rim's chroma at each whole degree of hue.
    private static let rims: [Double] = (0..<360).map { rim(exact: Double($0)) }

    /// The most chroma sRGB shows of `hue` at the wheel's lightness, and no
    /// more than the wash ever draws (OKLab.mostChroma).
    static func rim(exact hue: Double) -> Double {
        if OKLab(lightness: lightness, chroma: OKLab.mostChroma, hue: hue).fits { return OKLab.mostChroma }
        var low = 0.0, high = OKLab.mostChroma
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if OKLab(lightness: lightness, chroma: mid, hue: hue).fits { low = mid } else { high = mid }
        }
        return low
    }

    static func rim(_ hue: Double) -> Double {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        // The lesser of the two degrees either side: between them the rim
        // can bow inwards, and the wheel should never show what sRGB can't.
        let at = Int(h) % 360, next = (at + 1) % 360
        return min(rims[at], rims[next]) * 0.998
    }

    static func hue(at point: CGPoint) -> Double {
        let degrees = (atan2(point.y, point.x) * 180 / .pi + turn).truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The colour at `point`; beyond the rim is the rim.
    static func colour(at point: CGPoint) -> OKLab {
        let out = min(hypot(point.x, point.y), 1)
        let hue = hue(at: point)
        return OKLab(lightness: lightness, chroma: out * rim(hue), hue: hue)
    }

    /// Where `colour` lies: its hue round, its chroma out, no further than
    /// the rim. Its lightness doesn't show; the wheel has the one.
    static func point(for colour: OKLab) -> CGPoint {
        guard colour.chroma > 1e-4 else { return .zero }
        let hue = colour.hue
        let out = min(colour.chroma / max(rim(hue), 1e-6), 1)
        let angle = (hue - turn) * .pi / 180
        return CGPoint(x: out * cos(angle), y: out * sin(angle))
    }

    static func point(for hex: String) -> CGPoint? { OKLab(hex: hex).map(point(for:)) }

    /// `point` held to the wheel's face.
    static func inside(_ point: CGPoint) -> CGPoint {
        let out = hypot(point.x, point.y)
        return out > 1 ? CGPoint(x: point.x / out, y: point.y / out) : point
    }

    /// Where a handle snaps: the twelve hues the ready-made gradients are
    /// made of, and the grey middle.
    static let snaps: [(point: CGPoint, hex: String)] = {
        let hues = SpaceGradient.swatches.prefix(12).map { (point(for: $0.hex) ?? .zero, $0.hex) }
        return hues + [(CGPoint.zero, OKLab(L: lightness, a: 0, b: 0).hex)]
    }()

    /// How near a snap a handle has to come to be caught by it, as a share
    /// of the radius: about ten points on the picker's wheel.
    static let pull = 0.085

    /// `point` on the wheel, caught by a snap if it is near one: the spot,
    /// and which snap.
    static func snapped(_ point: CGPoint) -> (point: CGPoint, snap: Int?) {
        let spot = inside(point)
        var best: (at: Int, distance: Double)?
        for (at, snap) in snaps.enumerated() {
            let distance = hypot(spot.x - snap.point.x, spot.y - snap.point.y)
            if distance < pull, distance < (best?.distance ?? .infinity) { best = (at, distance) }
        }
        guard let best else { return (spot, nil) }
        return (snaps[best.at].point, best.at)
    }

    /// The colour a handle let go at `point` picks: a snap's own, so a
    /// handle on Teal is Teal exactly and the ready-made gradients come
    /// back as themselves, or the colour under it.
    static func hex(at point: CGPoint) -> String {
        let (spot, snap) = snapped(point)
        return snap.map { snaps[$0].hex } ?? colour(at: spot).hex
    }

    /// Where a new handle goes: round the wheel from the last one and at
    /// least as far out, so the colour it adds is a neighbour worth having,
    /// not a grey; on the first, Blue.
    static func beside(_ points: [CGPoint]) -> CGPoint {
        guard let last = points.last else { return snaps[7].point }
        let out = max(hypot(last.x, last.y), 0.62)
        let angle = atan2(last.y, last.x) + 75 * .pi / 180
        return snapped(CGPoint(x: out * cos(angle), y: out * sin(angle))).point
    }

    /// The wheel as a picture `side` points across, two pixels a point,
    /// with a soft edge. Made once for each size.
    @MainActor static func image(side: CGFloat) -> NSImage {
        if let made = images[side] { return made }
        let scale: CGFloat = 2
        let pixels = Int((side * scale).rounded())
        let radius = Double(pixels) / 2
        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let dx = (Double(x) + 0.5 - radius), dy = (Double(y) + 0.5 - radius)
                let distance = hypot(dx, dy)
                let alpha = min(max(radius - distance, 0), 1)
                guard alpha > 0 else { continue }
                let (r, g, b) = colour(at: CGPoint(x: dx / radius, y: dy / radius)).srgb
                let at = (y * pixels + x) * 4
                bytes[at] = UInt8((r * alpha * 255).rounded())
                bytes[at + 1] = UInt8((g * alpha * 255).rounded())
                bytes[at + 2] = UInt8((b * alpha * 255).rounded())
                bytes[at + 3] = UInt8((alpha * 255).rounded())
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let made: NSImage
        if let provider = CGDataProvider(data: Data(bytes) as CFData),
           let cg = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
                            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            made = NSImage(cgImage: cg, size: NSSize(width: side, height: side))
        } else {
            made = NSImage(size: NSSize(width: side, height: side))
        }
        images[side] = made
        return made
    }

    @MainActor private static var images: [CGFloat: NSImage] = [:]
}

// MARK: - drawing

/// The window's size, for a gradient to run across the whole of it (see
/// SpaceGradient.points). Zero off screen, where each draws its own.
private struct WashRoomKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

/// How strongly the space on screen washes the chrome, set once for the
/// whole window beside washRoom, so every SpaceWash draws alike.
private struct WashStrengthKey: EnvironmentKey {
    static let defaultValue = SpaceStrength.subtle
}

/// How much grain lies over the wash, the same way.
private struct WashGrainKey: EnvironmentKey {
    static let defaultValue = 0.0
}

extension EnvironmentValues {
    var washRoom: CGSize {
        get { self[WashRoomKey.self] }
        set { self[WashRoomKey.self] = newValue }
    }

    var washStrength: SpaceStrength {
        get { self[WashStrengthKey.self] }
        set { self[WashStrengthKey.self] = newValue }
    }

    var washGrain: Double {
        get { self[WashGrainKey.self] }
        set { self[WashGrainKey.self] = newValue }
    }
}

/// A space's gradient, at the wash's strength.
struct GradientWash: View {
    let gradient: SpaceGradient
    let strength: SpaceStrength
    @Environment(\.washRoom) private var room
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let ends = gradient.points(frame: geo.frame(in: .global), room: room)
            let dark = scheme == .dark
            LinearGradient(stops: gradient.stops(strength: strength, dark: dark), startPoint: ends.start, endPoint: ends.end)
                .opacity(strength.opacity(dark: dark))
        }
        .allowsHitTesting(false)
    }
}

/// The grain over a wash: the tile, laid edge to edge, as much of it as
/// `opacity` shows.
struct GrainWash: View {
    let opacity: Double

    var body: some View {
        Image(nsImage: Grain.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// The grain: noise, half lighter and half darker than what is under it,
/// in one tile made the first time it is wanted, and tiled. Never moves.
enum Grain {
    /// How much of the tile showed with a gradient's grain switched on,
    /// before amounts: faint enough to be felt rather than seen as dots.
    static let light = 0.035
    static let dark = 0.04
    /// The amount that is, the grain a space from then keeps. The most,
    /// 1, is about two and a half times that (see felt): the film grain of
    /// Arc's themes, short of the column's faintest ink having to fight it.
    static let legacy = 0.3

    /// The amount as drawn: as set up to the old switch's, then gentler, so
    /// the slider's far end is film grain and not sand (Nov 2026: the most
    /// was three and a third times the old grain, now about two and a half).
    static func felt(_ amount: Double) -> Double {
        let amount = min(max(amount, 0), 1)
        return amount <= legacy ? amount : legacy + (amount - legacy) * 0.6
    }

    @MainActor static let tile: NSImage = {
        let side = 192
        // The same noise every launch: a little generator of our own.
        var seed: UInt32 = 0x9E3779B9
        func next() -> Double {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Double(seed) / Double(UInt32.max)
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: side * 4, bitsPerPixel: 32)
        if let pixels = rep?.bitmapData {
            for i in 0..<(side * side) {
                // Two draws together lean to the middle, as film's grain
                // does: mostly fine, now and then a coarser speck.
                // Premultiplied: white or black, by how far from the middle.
                let v = next() + next() - 1
                let alpha = UInt8(min(abs(v) * 1.4, 1) * 255)
                let ink: UInt8 = v > 0 ? alpha : 0
                pixels[i * 4] = ink; pixels[i * 4 + 1] = ink; pixels[i * 4 + 2] = ink; pixels[i * 4 + 3] = alpha
            }
        }
        // Two pixels a point: one grain to a pixel on a Retina screen.
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        if let rep { image.addRepresentation(rep) }
        return image
    }()
}

/// The Colour… picker's live preview: the look a handle or the grain is
/// being dragged to, shown on every wash of that space at once, without
/// touching the space — nothing written, nothing else in the window drawn
/// again — until the drag ends and it is kept (`end`).
@MainActor
final class LookDraft: ObservableObject {
    static let shared = LookDraft()

    struct Preview: Equatable {
        var space: UUID
        var look: SpaceLook?
        var strength: SpaceStrength
        var grain: Double
    }

    @Published private(set) var preview: Preview?
    /// How many looks a drag has shown: for the bench, to see that a drag
    /// draws without writing.
    private(set) var shown = 0

    func preview(for space: UUID?) -> Preview? {
        guard let space, let preview, preview.space == space else { return nil }
        return preview
    }

    func show(_ preview: Preview) {
        guard self.preview != preview else { return }
        shown += 1
        self.preview = preview
    }

    /// The drag over: `keep` makes the look the space's own, and the
    /// preview gives way to it in the same frame. They look the same, so
    /// nothing crossfades.
    func end(keeping keep: () -> Void = {}) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            keep()
            preview = nil
        }
    }
}

// MARK: - choosing

/// What a space wears, as the picker names it: nothing, one of the colours,
/// one of the ready-made gradients, or a colour or gradient of one's own.
enum SpaceLookChoice: Equatable {
    case none
    case colour(Int)
    case preset(Int)
    case custom
}

extension SpaceLook {
    /// What the picker's header calls it.
    var name: String {
        switch self {
        case .colour(let colour): return Spaces.colourNames.indices.contains(colour) ? Spaces.colourNames[colour] : "Colour"
        case .gradient(let gradient):
            if let at = SpaceGradient.presets.firstIndex(where: { $0.gradient.colours == gradient.colours }) {
                return SpaceGradient.presets[at].name
            }
            return gradient.single ? "Custom colour" : "Custom gradient"
        }
    }
}

extension Space {
    var lookChoice: SpaceLookChoice {
        if let gradient, gradient.usable {
            let at = SpaceGradient.presets.firstIndex { $0.gradient.colours == gradient.colours }
            return at.map(SpaceLookChoice.preset) ?? .custom
        }
        return colour > 0 && Spaces.colours.indices.contains(colour) ? .colour(colour) : .none
    }

    /// What the picker's header says it is.
    var lookName: String { look?.name ?? "No colour" }

    /// The colours the wheel's handles stand for: its own colour or
    /// gradient's, or the one of Spaces.colours it wears, or none.
    var wheelColours: [String] {
        if let gradient, gradient.usable {
            return Array(gradient.colours.filter { OKLab(hex: $0) != nil }.prefix(SpaceGradient.most))
        }
        guard colour > 0, Spaces.colours.indices.contains(colour),
              let c = NSColor(Spaces.colours[colour]).usingColorSpace(.sRGB) else { return [] }
        return [OKLab(r: c.redComponent, g: c.greenComponent, b: c.blueComponent).hex]
    }
}

extension Browser {
    /// A choice in the picker, made to the space at once: the window is the
    /// preview. A colour (or none) takes the gradient away; a ready-made
    /// gradient keeps the direction and grain the space's gradient had.
    func chooseLook(_ id: UUID, _ choice: SpaceLookChoice) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        let current = space.gradient.flatMap { $0.usable ? $0 : nil }
        switch choice {
        case .none: setSpaceColour(id, to: 0)
        case .colour(let colour): setSpaceColour(id, to: colour)
        case .preset(let at):
            guard SpaceGradient.presets.indices.contains(at) else { return }
            setSpaceGradient(id, to: SpaceGradient(colours: SpaceGradient.presets[at].gradient.colours,
                                                   angle: current?.angle ?? SpaceGradient.defaultAngle,
                                                   grain: space.grainAmount > 0))
        case .custom:
            setSpaceGradient(id, to: current ?? SpaceGradient.starting(from: space.colour))
        }
    }

    /// The space's own gradient changed by `change`: its current one, or a
    /// first one from its colour.
    func editGradient(_ id: UUID, _ change: (inout SpaceGradient) -> Void) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        var gradient = space.gradient.flatMap { $0.usable ? $0 : nil } ?? SpaceGradient.starting(from: space.colour)
        change(&gradient)
        setSpaceGradient(id, to: gradient)
    }

    /// The look the wheel's handles make, before it is kept: their colours
    /// (one to three), in the direction the space's gradient runs. Nil for
    /// no handles.
    func wheelGradient(_ id: UUID, colours: [String]) -> SpaceGradient? {
        guard let space = spaces.first(where: { $0.id == id }) else { return nil }
        let colours = Array(colours.filter { OKLab(hex: $0) != nil }.prefix(SpaceGradient.most))
        guard !colours.isEmpty else { return nil }
        let current = space.gradient.flatMap { $0.usable ? $0 : nil }
        return SpaceGradient(colours: colours, angle: current?.angle ?? SpaceGradient.defaultAngle, grain: space.grainAmount > 0)
    }

    /// The wheel's handles kept as the space's look.
    func setWheel(_ id: UUID, colours: [String]) {
        guard let gradient = wheelGradient(id, colours: colours) else { return }
        setSpaceGradient(id, to: gradient)
    }

    /// A handle added to the wheel beside the others (ColourWheel.beside):
    /// a colour of its own, then a gradient, of three at most. Which it is.
    @discardableResult
    func addWheelHandle(_ id: UUID) -> Int? {
        guard let space = spaces.first(where: { $0.id == id }) else { return nil }
        let colours = space.wheelColours
        guard colours.count < SpaceGradient.most else { return nil }
        let spot = ColourWheel.beside(colours.compactMap(ColourWheel.point(for:)))
        setWheel(id, colours: colours + [ColourWheel.hex(at: spot)])
        return colours.count
    }

    /// A handle taken off the wheel; the last one stays.
    func removeWheelHandle(_ id: UUID, at index: Int) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        var colours = space.wheelColours
        guard colours.count > 1 else { return }
        colours.remove(at: min(max(index, 0), colours.count - 1))
        setWheel(id, colours: colours)
    }

    /// The gradient turned an eighth of the way round, as the wheel's arrow does.
    func turnGradient(_ id: UUID, by degrees: Double = 45) {
        editGradient(id) {
            let turned = ($0.angle + degrees).truncatingRemainder(dividingBy: 360)
            $0.angle = turned < 0 ? turned + 360 : turned
        }
    }

    /// Back to a look exactly as it was: Escape in the picker. One write.
    func restoreLook(_ id: UUID, colour: Int, gradient: SpaceGradient?, strength: SpaceStrength? = nil, grain: SpaceGrain? = nil) {
        guard let at = spaces.firstIndex(where: { $0.id == id }), Spaces.colours.indices.contains(colour) else { return }
        spaces[at].colour = colour
        spaces[at].gradient = gradient.flatMap { $0.usable ? $0 : nil }
        spaces[at].strength = strength == .subtle ? nil : strength
        spaces[at].grain = grain.flatMap { $0.amount > 0 ? $0 : nil }
        Spaces.write(spaces, profile: profileID)
    }
}

// MARK: - the picker

/// Colour…: everything a space can wear, in one popover by its icon, as
/// Arc's. A wheel to pick one, two or three colours on, by dragging their
/// handles — they snap to the ready-made hues and the grey middle, and
/// spring as they go — with + and − for a handle more or less, and an arrow
/// that turns the gradient. Under it the ready-made looks, None among them;
/// then grain, strength and the window's appearance.
///
/// The window is the preview. While a handle or the grain is dragged the
/// washes show it at once (LookDraft) and nothing is written; letting go
/// keeps it. A click elsewhere keeps what is there, Escape puts back what
/// the space had when the picker opened.
struct SpaceLookPicker: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var prefs: Preferences
    @ObservedObject private var draft = LookDraft.shared
    let id: UUID

    /// The handles while one is dragged, in the wheel's terms (ColourWheel);
    /// nil when none is, and they are where the space's colours put them.
    @State private var held: [CGPoint]?
    @State private var dragging: Int?
    /// The handle + and − and a click on the wheel move.
    @State private var selected = 0
    /// The snap a dragged handle is caught by, for the tick as it lands.
    @State private var caught: Int?
    /// The grain while its slider is dragged.
    @State private var grainHeld: Double?
    /// The arrow's turn, counted on rather than wrapped, so it never spins
    /// the long way round from 315° to 0°.
    @State private var turned: Double
    @Namespace private var segments

    static let width: CGFloat = 296
    static let wheel: CGFloat = 208
    static let handle: CGFloat = 24
    static let dot: CGFloat = 24

    init(browser: Browser, id: UUID) {
        self.browser = browser
        self.id = id
        _prefs = ObservedObject(wrappedValue: browser.prefs)
        let space = browser.spaces.first { $0.id == id } ?? browser.space
        _turned = State(initialValue: space.gradient?.angle ?? SpaceGradient.defaultAngle)
    }

    private var space: Space { browser.spaces.first { $0.id == id } ?? browser.space }
    private var angle: Double { space.gradient.flatMap { $0.usable ? $0.angle : nil } ?? SpaceGradient.defaultAngle }
    /// What the window shows: the look being dragged to, or the space's.
    private var shownLook: SpaceLook? { draft.preview(for: id).map(\.look) ?? space.look }
    private var points: [CGPoint] { held ?? space.wheelColours.compactMap(ColourWheel.point(for:)) }
    private var grain: Double { grainHeld ?? space.grainAmount }

    /// Springs: one that bounces a little for what lands — a snap, a preset,
    /// a handle let go — and a tight one that follows the pointer.
    // A handle caught, a stop added or taken away: a click, not a throw, so
    // it lands without the bounce it had (Motion.settle's reasoning).
    private var bouncy: Animation? { Motion.reduced ? nil : .spring(response: 0.32, dampingFraction: 1) }
    private var following: Animation? { Motion.reduced ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.78) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            wheelArea
            presets
            VStack(spacing: 10) {
                row("Grain") { grainControl }
                row("Strength") { strengthControl }
                row("Appearance") { appearanceControl }
            }
        }
        .padding(16)
        .frame(width: Self.width + (roomy ? 28 : 0), alignment: .leading)
        .onChange(of: angle) { _, new in
            if abs((turned - new).truncatingRemainder(dividingBy: 360)) > 0.5 { turned = new }
        }
        .onDisappear { if draft.preview(for: id) != nil { draft.end() } }
    }

    // MARK: header

    /// The space's icon on its look, and what the look is called.
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                LookFill(look: shownLook, angle: angle, grain: draft.preview(for: id)?.grain ?? grain,
                         shape: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Image(systemName: space.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(shownLook == nil ? Palette.muted : Color.white)
                    .shadow(color: .black.opacity(shownLook == nil ? 0 : 0.2), radius: 1.5, y: 0.5)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(shownLook?.name ?? "No colour")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(space.name): \(shownLook?.name ?? "No colour")")
    }

    // MARK: wheel

    private var wheelArea: some View {
        let points = points
        let side = Self.wheel
        return ZStack {
            Image(nsImage: ColourWheel.image(side: side))
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            // Where a handle snaps: faint, so the eye finds them and the
            // wheel still reads as one smooth thing.
            ForEach(ColourWheel.snaps.indices, id: \.self) { at in
                Circle()
                    .fill(Color.white.opacity(caught == at ? 0.95 : 0.5))
                    .frame(width: caught == at ? 6 : 3.5, height: caught == at ? 6 : 3.5)
                    .position(spot(ColourWheel.snaps[at].point))
                    .animation(bouncy, value: caught)
            }
            // The order the colours run in, as a thread through the handles.
            if points.count > 1 {
                Thread(points: points.map(spot))
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                    .transition(.opacity)
            }
            ForEach(points.indices, id: \.self) { at in
                handle(at, points)
            }
            if points.isEmpty {
                Text("Click to pick a colour")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.regularMaterial))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .gesture(drag)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if points.count > 1 {
                round("arrow.up", "Turn the Gradient", rotation: turned) {
                    turned += 45
                    browser.turnGradient(id)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if points.count > 1 {
                round("minus", "Remove a Colour") {
                    let at = min(selected, points.count - 1)
                    withAnimation(bouncy) {
                        browser.removeWheelHandle(id, at: at)
                        selected = max(0, min(at, points.count - 2))
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if points.count < SpaceGradient.most {
                round("plus", "Add a Colour") {
                    withAnimation(bouncy) {
                        if let added = browser.addWheelHandle(id) { selected = added }
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(bouncy, value: points.count)
    }

    private func handle(_ at: Int, _ points: [CGPoint]) -> some View {
        let lab = ColourWheel.colour(at: points[at])
        let (r, g, b) = (held == nil ? space.wheelColours[safe: at].flatMap(OKLab.init(hex:)) ?? lab : lab).srgb
        let lifted = dragging == at
        return Circle()
            .fill(Color(.sRGB, red: r, green: g, blue: b))
            .frame(width: Self.handle, height: Self.handle)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
            // A hairline outside the white, so a handle holds its edge on
            // the wheel's palest stretch too.
            .overlay(Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5).padding(-0.5))
            .overlay {
                // The one + and − and a click move, when there is a choice.
                if selected == at, points.count > 1 {
                    Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5).padding(-4)
                }
            }
            .shadow(color: .black.opacity(lifted ? 0.32 : 0.26), radius: lifted ? 6 : 2.5, y: lifted ? 3 : 1)
            .scaleEffect(lifted ? 1.3 : 1)
            .position(spot(points[at]))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .accessibilityElement()
            .accessibilityLabel("Colour \(at + 1)")
            .accessibilityValue(OKLab(r: r, g: g, b: b).hex)
    }

    /// A spot on the wheel in its own points.
    private func spot(_ point: CGPoint) -> CGPoint {
        let radius = Self.wheel / 2
        return CGPoint(x: radius + point.x * radius, y: radius + point.y * radius)
    }

    /// A spot in the wheel's own points, on the wheel's terms.
    private func unit(_ location: CGPoint) -> CGPoint {
        let radius = Self.wheel / 2
        return CGPoint(x: (location.x - radius) / radius, y: (location.y - radius) / radius)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil { grab(unit(value.startLocation)) }
                guard let dragging, var moved = held, moved.indices.contains(dragging) else { return }
                let (spot, snap) = ColourWheel.snapped(unit(value.location))
                let landed = snap != nil && snap != caught
                if snap != caught {
                    if snap != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                    caught = snap
                }
                moved[dragging] = spot
                withAnimation(landed ? bouncy : following) { held = moved }
                show(moved)
            }
            .onEnded { _ in letGo() }
    }

    /// A press on the wheel: on a handle, that handle; elsewhere, the
    /// chosen handle comes to it; on an empty wheel, a first one.
    private func grab(_ at: CGPoint) {
        var list = points
        let reach = (Self.handle / 2 + 8) / (Self.wheel / 2)
        let nearest = list.indices.min { hypot(list[$0].x - at.x, list[$0].y - at.y) < hypot(list[$1].x - at.x, list[$1].y - at.y) }
        let index: Int
        if let nearest, hypot(list[nearest].x - at.x, list[nearest].y - at.y) <= reach {
            index = nearest
        } else if list.isEmpty {
            list = [ColourWheel.inside(at)]
            index = 0
        } else {
            index = min(selected, list.count - 1)
        }
        held = list
        caught = nil
        withAnimation(bouncy) {
            dragging = index
            selected = index
        }
    }

    /// The handle let go: kept, and the preview gives way to it.
    private func letGo() {
        guard let moved = held else { dragging = nil; return }
        let colours = moved.map(ColourWheel.hex(at:))
        draft.end {
            browser.setWheel(id, colours: colours)
            held = nil
        }
        caught = nil
        withAnimation(bouncy) { dragging = nil }
    }

    /// The look the handles make, on the window at once.
    private func show(_ moved: [CGPoint]) {
        guard let gradient = browser.wheelGradient(id, colours: moved.map(ColourWheel.hex(at:))) else { return }
        draft.show(LookDraft.Preview(space: id, look: .gradient(gradient), strength: space.washStrength, grain: grain))
    }

    // MARK: presets

    /// None, the five colours, and the six ready-made gradients.
    private var presets: some View {
        let choice = draft.preview(for: id) == nil ? space.lookChoice : .custom
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                swatch(selected: choice == .none, name: "None", action: { pick(.none) }) {
                    ZStack {
                        Circle().fill(Palette.ground)
                        Circle().strokeBorder(Palette.faint, lineWidth: 1)
                        Rectangle().fill(Palette.faint).frame(width: 1, height: Self.dot - 6).rotationEffect(.degrees(45))
                    }
                }
                ForEach(1..<Spaces.colours.count, id: \.self) { index in
                    swatch(selected: choice == .colour(index), name: Spaces.colourNames[index], action: { pick(.colour(index)) }) {
                        Circle().fill(Spaces.colours[index])
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(SpaceGradient.presets.indices, id: \.self) { at in
                    let preset = SpaceGradient.presets[at]
                    swatch(selected: choice == .preset(at), name: preset.name, action: { pick(.preset(at)) }) {
                        Circle().fill(LinearGradient(stops: preset.gradient.stops(count: 8),
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
        }
    }

    private func pick(_ choice: SpaceLookChoice) {
        withAnimation(bouncy) {
            browser.chooseLook(id, choice)
            selected = 0
        }
    }

    // MARK: grain, strength, appearance

    private var grainControl: some View {
        let off = shownLook == nil
        return HStack(spacing: 10) {
            GrainSlider(value: grain, look: shownLook, angle: angle, tall: roomy ? 26 : 20) { amount in
                grainHeld = amount
                draft.show(LookDraft.Preview(space: id, look: space.look, strength: space.washStrength, grain: amount))
            } done: { amount in
                draft.end {
                    browser.setSpaceGrain(id, to: amount)
                    grainHeld = nil
                }
            }
            Text(grain < 0.005 ? "None" : "\(Int((grain * 100).rounded()))%")
                .font(.system(size: roomy ? 12.5 : 11).monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(width: roomy ? 38 : 34, alignment: .trailing)
        }
        .opacity(off ? 0.45 : 1)
        .disabled(off)
        .help(off ? "Choose a colour first" : "Film grain over the space's colour")
    }

    /// Subtle, Rich or Vivid, for the colour and the gradient alike. With no
    /// colour there is nothing to strengthen: shown, but not to be had.
    private var strengthControl: some View {
        let off = shownLook == nil
        return segmented(SpaceStrength.allCases.map { ($0, $0.name, nil) }, selection: space.washStrength, key: "strength") {
            browser.setSpaceStrength(id, to: $0)
        }
        .opacity(off ? 0.45 : 1)
        .disabled(off)
        .help(off ? "Choose a colour first" : "How strongly the space's colour shows")
    }

    /// The window's appearance, as in Settings › Appearance: for every
    /// space, here to see the look both ways.
    private var appearanceControl: some View {
        segmented([(Look.system, "Auto", "circle.lefthalf.filled"), (.light, "Light", "sun.max"), (.dark, "Dark", "moon")],
                  selection: prefs.look, key: "look") { prefs.look = $0 }
            .help("Light, dark or the Mac's own, for every space, as in Settings › Appearance")
    }

    /// Roomy: the rows and their controls a size up, as the column's are.
    private var roomy: Bool { prefs.roomyTabs }

    private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: roomy ? 12.5 : 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: roomy ? 80 : 70, alignment: .leading)
            content()
        }
    }

    /// A small segmented row whose lit segment slides to the one chosen.
    private func segmented<T: Hashable>(_ options: [(T, String, String?)], selection: T, key: String,
                                        action: @escaping (T) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { at in
                let option = options[at]
                let on = option.0 == selection
                Button {
                    withAnimation(bouncy) { action(option.0) }
                } label: {
                    HStack(spacing: roomy ? 5 : 4) {
                        if let symbol = option.2 { Image(systemName: symbol).font(.system(size: roomy ? 10.5 : 9, weight: .semibold)) }
                        Text(option.1).font(.system(size: roomy ? 12.5 : 11, weight: on ? .medium : .regular))
                    }
                    .foregroundStyle(on ? Palette.ink : Palette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: roomy ? 28 : 22)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: roomy ? 7 : 5, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: key, in: segments)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(option.1)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: roomy ? 9 : 7, style: .continuous).fill(Palette.hover))
    }

    // MARK: pieces

    /// One size for every choice: the dot, and a ring round the one chosen.
    private func swatch(selected: Bool, name: String, action: @escaping () -> Void,
                        @ViewBuilder _ fill: () -> some View) -> some View {
        Swatch(selected: selected, name: name, size: Self.dot, action: action, fill: fill())
            .frame(maxWidth: .infinity)
    }

    private func round(_ symbol: String, _ name: String, rotation: Double = 0, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(rotation))
                .animation(bouncy, value: rotation)
                .foregroundStyle(Palette.ink.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.hover))
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(Pressy())
        .help(name)
        .accessibilityLabel(name)
    }
}

/// A look, filling a shape: the colour, or the gradient its way, with its
/// grain; a grey for none.
private struct LookFill<S: Shape>: View {
    let look: SpaceLook?
    let angle: Double
    let grain: Double
    let shape: S

    var body: some View {
        ZStack {
            switch look {
            case nil: shape.fill(Palette.hover)
            case .colour(let colour)?: shape.fill(Spaces.colours.indices.contains(colour) ? Spaces.colours[colour] : .gray)
            case .gradient(let gradient)?:
                let ends = gradient.points(frame: CGRect(x: 0, y: 0, width: 1, height: 1), room: .zero)
                shape.fill(LinearGradient(stops: gradient.stops(count: 8), startPoint: ends.start, endPoint: ends.end))
            }
            if look != nil, grain > 0 {
                GrainWash(opacity: min(grain * 0.5, 0.5)).clipShape(shape)
            }
        }
    }
}

/// A swatch: springs up a touch under the pointer, and gives when pressed.
private struct Swatch<Fill: View>: View {
    let selected: Bool
    let name: String
    let size: CGFloat
    let action: () -> Void
    let fill: Fill
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            fill
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Palette.ink.opacity(0.75) : .clear, lineWidth: 1.5))
                .scaleEffect(hovering ? 1.1 : 1)
                .animation(Motion.settle, value: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(Pressy())
        .onHover { hovering = $0 }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A button that gives a little when pressed and springs back.
private struct Pressy: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.94 : 1)
            // Instant on the press, back without a bounce (PressStyle).
            .animation(Motion.out(configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

/// The line through the handles, in the order the colours run. Its points
/// move as the handles do, on the same springs.
private struct Thread: Shape {
    var points: [CGPoint]

    var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGPoint.AnimatableData> {
        get {
            let a = points.first ?? .zero, b = points.count > 1 ? points[1] : a, c = points.count > 2 ? points[2] : b
            return AnimatablePair(AnimatablePair(a.animatableData, b.animatableData), c.animatableData)
        }
        set {
            var a = CGPoint.zero, b = CGPoint.zero, c = CGPoint.zero
            a.animatableData = newValue.first.first
            b.animatableData = newValue.first.second
            c.animatableData = newValue.second
            points = Array([a, b, c].prefix(max(points.count, 1)))
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

/// Grain's slider: a track that wears the space's look with grain growing
/// along it, and a knob that swells while held. `changed` follows the drag,
/// `done` is the amount let go at.
private struct GrainSlider: View {
    let value: Double
    let look: SpaceLook?
    let angle: Double
    /// Its height: 20 points, more with Roomy; the knob a little less.
    var tall: CGFloat = 20
    let changed: (Double) -> Void
    let done: (Double) -> Void
    @State private var holding = false
    private var knob: CGFloat { tall - 2 }

    static let knob: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let track = RoundedRectangle(cornerRadius: tall / 2, style: .continuous)
            let room = max(geo.size.width - knob - 2, 1)
            ZStack(alignment: .leading) {
                LookFill(look: look, angle: 90, grain: 0, shape: track)
                    .opacity(look == nil ? 1 : 0.85)
                // The grain, from none at the left to the most at the right.
                GrainWash(opacity: 0.9)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                    .clipShape(track)
                track.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: holding ? 4 : 2, y: holding ? 2 : 1)
                    .scaleEffect(holding ? 1.2 : 1)
                    .offset(x: 1 + room * value)
                    .animation(Motion.settle, value: holding)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        holding = true
                        changed(Self.amount(at: drag.location.x, room: room, knob: knob))
                    }
                    .onEnded { drag in
                        holding = false
                        done(Self.amount(at: drag.location.x, room: room, knob: knob))
                    }
            )
        }
        .frame(height: tall)
        .accessibilityElement()
        .accessibilityLabel("Grain")
        .accessibilityValue(value < 0.005 ? "None" : "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            done(min(max(value + step, 0), 1))
        }
    }

    static func amount(at x: CGFloat, room: CGFloat, knob: CGFloat = knob) -> Double {
        // Held to whole hundredths, and a touch of none at the left end.
        let raw = Double((x - 1 - knob / 2) / room)
        return raw < 0.02 ? 0 : SpaceGrain(raw).amount
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The picker, shown by the space's icon where its menu was opened.
@MainActor
enum SpaceLookPopover {
    private final class Watch: NSObject, NSPopoverDelegate {
        var keys: Any?
        func popoverDidClose(_ notification: Notification) {
            if let keys { NSEvent.removeMonitor(keys) }
            keys = nil
            SpaceLookPopover.shown = nil
            // A drag the popover closed under: nothing kept but what was.
            if LookDraft.shared.preview != nil { LookDraft.shared.end() }
        }
    }

    fileprivate static var shown: NSPopover?
    private static let watch = Watch()
    /// Where the space's menu was last opened, on screen: the icon.
    static var anchor: NSPoint?

    static func show(for browser: Browser) {
        // A probe's window is never shown (Tests/space_gradient.py chooses
        // through the bench), and a popover is a window.
        guard ProcessInfo.processInfo.environment["SEARCH_PROBE"] == nil,
              let window = browser.window, window.isVisible, let content = window.contentView else { return }
        shown?.close()
        let space = browser.space
        let before = (colour: space.colour, gradient: space.gradient, strength: space.strength, grain: space.grain,
                      look: browser.prefs.look)
        let host = NSHostingController(rootView: SpaceLookPicker(browser: browser, id: space.id))
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = !Motion.instant
        popover.delegate = watch
        shown = popover
        // Escape puts back what the space had, and the window's appearance;
        // a click elsewhere keeps it.
        watch.keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak browser, weak popover] event in
            guard event.keyCode == 53, let popover, event.window === popover.contentViewController?.view.window else { return event }
            LookDraft.shared.end()
            browser?.restoreLook(space.id, colour: before.colour, gradient: before.gradient, strength: before.strength, grain: before.grain)
            if browser?.prefs.look != before.look { browser?.prefs.look = before.look }
            popover.close()
            return nil
        }

        let flipped = content.isFlipped
        var spot: NSRect
        if let anchor {
            let point = content.convert(window.convertPoint(fromScreen: anchor), from: nil)
            spot = NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
        } else {
            let bounds = content.bounds
            spot = NSRect(x: bounds.minX + 24, y: flipped ? bounds.maxY - 24 : bounds.minY + 24, width: 1, height: 1)
        }
        if !content.bounds.contains(spot.origin) { spot.origin = NSPoint(x: content.bounds.midX, y: content.bounds.midY) }
        let edge: NSRectEdge = browser.prefs.sidebar
            ? (browser.prefs.sidePosition == .right ? .minX : .maxX)
            : (flipped ? .maxY : .minY)
        popover.show(relativeTo: spot, of: content, preferredEdge: edge)
    }
}
