import SwiftUI
import UIKit

// Quo's look on iOS, from DESIGN.md: greys in pairs for light and dark, the
// system face a step larger than the Mac's, quiet depth, and the Mac's
// motion tokens.

enum Q {
    // MARK: colour

    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let ground = pair(0xFFFFFF, 0x1C1C1C)
    static let frame = pair(0xF4F4F4, 0x131313)
    static let ink = pair(0x171717, 0xEDEDED)
    static let muted = pair(0x8C8C8C, 0x949494)
    static let faint = pair(0xD4D4D4, 0x525252)
    static let hairline = pair(0xE8E8E8, 0x333333)
    static let wash = pair(0xEFEFEF, 0x2D2D2D)
    static let hover = pair(0xF6F6F6, 0x262626)
    static let safe = pair(0x14803D, 0x4ADE80)
    static let caution = pair(0xB5540A, 0xFABF24)

    /// A sheet's ground: a touch lifted from the frame in dark, white in light.
    static let sheet = pair(0xFFFFFF, 0x222222)
    /// A tile or a grouped row on a sheet.
    static let tile = pair(0xF2F2F2, 0x2D2D2D)

    /// The six space colours, as the Mac's.
    static let spaceColours: [Color] = [
        Color(red: 0.45, green: 0.47, blue: 0.52),
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.20, green: 0.66, blue: 0.45),
        Color(red: 0.96, green: 0.62, blue: 0.20),
        Color(red: 0.90, green: 0.33, blue: 0.40),
        Color(red: 0.62, green: 0.40, blue: 0.90),
    ]

    static func colour(of space: Space) -> Color {
        if let first = space.gradient?.hexes.first, let (r, g, b) = HexColour.parse(first) {
            return Color(red: r, green: g, blue: b)
        }
        return spaceColours.indices.contains(space.colour) ? spaceColours[space.colour] : spaceColours[0]
    }

    // MARK: type (DESIGN.md › For iOS)

    static let caption = Font.caption
    static let footnote = Font.footnote
    static let body = Font.subheadline
    static let bodyEmphasis = Font.subheadline.weight(.medium)
    static let callout = Font.headline
    static let title = Font.title3.weight(.semibold)

    // MARK: shape

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14
    static let radiusXL: CGFloat = 20

    // MARK: motion

    static let quick = Animation.easeOut(duration: 0.14)
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let glide = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let smooth = Animation.smooth(duration: 0.42)
    static let rise = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.88)
    /// The phone's own pace: quick to start, settled in about a quarter of
    /// a second, no bounce. Panels, cards and the bar move on this.
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.9)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Gives under a finger: 0.97 on `quick`.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Q.quick, value: configuration.isPressed)
    }
}

extension View {
    /// Floating depth: a hairline and a soft shadow.
    func floating(radius: CGFloat = Q.radiusLG) -> some View {
        self
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Q.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 8)
    }

    /// Respects Reduce Motion: the animation, or a short fade.
    func quoAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducedMotion(animation: animation, value: value))
    }
}

private struct ReducedMotion<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduce ? .easeOut(duration: 0.18) : animation, value: value)
    }
}

/// A round icon button, 44 points, an SF Symbol in medium weight.
struct RoundIcon: View {
    let symbol: String
    var size: CGFloat = 44
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Q.ink)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear), in: Circle())
                .overlay(Circle().strokeBorder(Q.hairline.opacity(filled ? 1 : 0), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// A site's mark: its icon if known, else its first letter on a wash.
struct SiteMark: View {
    let host: String?
    var size: CGFloat = 20
    @ObservedObject private var icons = Favicons.shared

    var body: some View {
        Group {
            if let host, let image = icons.image(for: host) {
                Image(uiImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Q.wash)
                    .overlay(
                        Text(Self.letter(host))
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(Q.muted)
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear { if let host { icons.want(host) } }
    }

    static func letter(_ host: String?) -> String {
        guard let host else { return "Q" }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare.first.map { String($0).uppercased() } ?? "Q"
    }
}

/// Apple's rules for things moved by a finger (Designing Fluid Interfaces,
/// WWDC 2018): let go, and what was moving carries on at the finger's speed
/// into a spring; flung, it lands where the momentum would take it; past
/// an end, it gives a little, less the further it goes.
enum Fling {
    /// Where a fling would come to rest, from its speed in points a second,
    /// as scrolling decelerates.
    static func project(_ velocity: CGFloat, rate: CGFloat = 0.998) -> CGFloat {
        velocity / 1000 * rate / (1 - rate)
    }

    /// How far something follows past an end: always a little, less the
    /// further, never a hard stop.
    static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard overshoot != 0 else { return 0 }
        let sign: CGFloat = overshoot < 0 ? -1 : 1
        let a = abs(overshoot)
        return sign * (a * dimension * constant) / (dimension + constant * a)
    }

    /// The spring that takes over from a finger: moving `from` toward `to`
    /// at `speed` (points a second) when let go. A settle, not a bounce:
    /// a little give, as after a throw.
    static func release(from: CGFloat, to: CGFloat, speed: CGFloat) -> Animation {
        let distance = to - from
        let relative = abs(distance) > 1 ? Double(speed / distance) : 0
        return .interpolatingSpring(Spring(response: 0.32, dampingRatio: 0.84), initialVelocity: max(-12, min(12, relative)))
    }
}

/// Touch you can feel, only where something was done (Apple's rules:
/// caused by the action, on the same frame as it, and only where it helps).
/// The generators are made once and kept warm, so a tap's feedback lands on
/// the frame it should.
@MainActor
enum Haptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    static func prepare() {
        soft.prepare(); light.prepare(); rigid.prepare(); selection.prepare(); notice.prepare()
    }

    /// A sheet a finger drew out or pushed away, landing.
    static func settle() { soft.impactOccurred(intensity: 0.7); soft.prepare() }
    /// Something small done: a link copied.
    static func tap() { light.impactOccurred(intensity: 0.6); light.prepare() }
    /// A card thrown away.
    static func toss() { rigid.impactOccurred(intensity: 0.55); rigid.prepare() }
    /// One of a set chosen: the next space.
    static func pick() { selection.selectionChanged(); selection.prepare() }
    /// Something kept: a page pinned.
    static func done() { notice.notificationOccurred(.success); notice.prepare() }
}

extension View {
    /// A title's tracking, tightened as Apple's type is at larger sizes;
    /// small text keeps the face's own spacing.
    func titleTracking() -> some View { tracking(-0.3) }
}
