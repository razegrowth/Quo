import SwiftUI

// While an agent is allowed in a window: a thin ring of light around the
// whole stage, every page on it, turning slowly, brighter while the agent is
// at work and resting while it's idle; and hanging from its top edge, like a
// tab of the ring, what is using Quo and Stop. It takes the place of the
// quiet line that was at the foot of the column and at the end of the
// address bar: one thing, where the eye already is, that says the browser is
// not only yours right now.
//
// Drawn by the stage over its pages (PaneStage.showAgent), so it is above
// WebKit; only the pill takes a click, and the page under the ring keeps
// every other one. Stop is pressed by a click of yours like any button; the
// agent's own clicks go into pages and never reach it.

struct AgentRing: View {
    @ObservedObject var browser: Browser
    var corner: CGFloat = 0
    /// Where the pill is, from the ring's top-left, so the stage lets
    /// clicks through everywhere else; .zero while there is none.
    var onPillFrame: (CGRect) -> Void = { _ in }
    /// Where each page on the stage is, by tab, from its top-left, for
    /// the pointer to land where the agent clicked.
    var pages: () -> [Tab.ID: CGRect] = { [:] }
    @ObservedObject private var agents = AgentControl.shared

    static let space = "AgentRing"

    /// The ring's colours: the accent, with a cooler and a warmer turn of it
    /// and gaps of almost nothing between, so bright arcs travel round
    /// rather than the whole edge glowing at once.
    static var colors: [Color] {
        [Color.accentColor, Color.accentColor.opacity(0.12), Color(red: 0.56, green: 0.45, blue: 1).opacity(0.9),
         Color.accentColor.opacity(0.12), Color(red: 1, green: 0.45, blue: 0.7).opacity(0.85), Color.accentColor]
    }

    var body: some View {
        ZStack {
            if let session = agents.session, session.browser === browser {
                AgentRingFace(session: session, corner: corner, onPillFrame: onPillFrame, pages: pages)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.settle, value: agents.session?.id)
        .onChange(of: agents.session == nil) { _, gone in if gone { onPillFrame(.zero) } }
    }
}

private struct AgentRingFace: View {
    @ObservedObject var session: AgentSession
    let corner: CGFloat
    let onPillFrame: (CGRect) -> Void
    let pages: () -> [Tab.ID: CGRect]
    @ObservedObject private var agents = AgentControl.shared

    private var on: Bool { session.consent.state == .allowed }

    var body: some View {
        ZStack(alignment: .top) {
            if on {
                AgentGlow(corner: corner, busy: session.busy)
                    .transition(.opacity)
                AgentPointerView(client: session.client, pointer: agents.pointer, pages: pages)
                AgentPill(line: session.justAdmitted ? AgentWords.admitted(session) : AgentWords.line(session),
                          auto: session.auto && !session.justAdmitted, busy: session.busy,
                          help: AgentWords.short(session))
                    .background {
                        GeometryReader { box in
                            Color.clear
                                .onAppear { onPillFrame(box.frame(in: .named(AgentRing.space))) }
                                .onChange(of: box.frame(in: .named(AgentRing.space))) { _, frame in onPillFrame(frame) }
                                .onDisappear { onPillFrame(.zero) }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(AgentRing.space))
        .animation(Motion.settle, value: on)
        .animation(.easeInOut(duration: 0.6), value: session.busy)
    }
}

/// The ring: a 2-point line just inside the stage's edge and a soft glow of
/// the same light inward, the colours going round once every 4 seconds
/// while the agent works and every 9 while it's idle, dimmer then. Still,
/// with Reduce Motion.
///
/// Turned by Core Animation, not redrawn: SwiftUI drawing a blurred
/// gradient the size of the page 30 times a second took the main thread
/// with it, and the whole browser stuttered while an agent worked. Here
/// the light is two layers whose turning the window server does on its
/// own; nothing in the app runs between frames. `still` draws it once, in
/// SwiftUI, for a picture.
private struct AgentGlow: View {
    let corner: CGFloat
    let busy: Bool
    var still = false

    var body: some View {
        Group {
            if still {
                let light = AngularGradient(colors: AgentRing.colors, center: .center)
                let shape = RoundedRectangle(cornerRadius: max(corner, 0), style: .continuous)
                ZStack {
                    shape.strokeBorder(light, lineWidth: 8).blur(radius: 10).opacity(busy ? 0.55 : 0.28)
                    shape.strokeBorder(light, lineWidth: 2).opacity(busy ? 1 : 0.6)
                }
            } else {
                AgentGlowLayers(corner: corner, busy: busy)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AgentGlowLayers: NSViewRepresentable {
    let corner: CGFloat
    let busy: Bool

    func makeNSView(context: Context) -> AgentGlowView { AgentGlowView() }

    func updateNSView(_ view: AgentGlowView, context: Context) {
        view.corner = corner
        view.busy = busy
    }
}

/// A conic gradient seen through a stroked rounded rectangle, twice: the
/// line, and a wider one with a soft edge for the glow. The gradient's
/// angle goes round with a keyframe animation on its end point.
final class AgentGlowView: NSView {
    var corner: CGFloat = 0 { didSet { if corner != oldValue { needsLayout = true } } }
    var busy = true { didSet { if busy != oldValue { turn() } } }

    private let line = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let lineMask = CAShapeLayer()
    private let glowMask = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for (gradient, mask) in [(glow, glowMask), (line, lineMask)] {
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            gradient.mask = mask
            mask.fillColor = nil
            mask.strokeColor = NSColor.black.cgColor
            layer?.addSublayer(gradient)
        }
        lineMask.lineWidth = 2
        glowMask.lineWidth = 8
        // A soft edge on the glow's mask: drawn once, since the path only
        // changes with the stage's size.
        glowMask.shadowColor = NSColor.black.cgColor
        glowMask.shadowOpacity = 1
        glowMask.shadowRadius = 9
        glowMask.shadowOffset = .zero
        paint()
        turn()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    /// The colours, resolved now: the accent follows the Mac's.
    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            let violet = NSColor(red: 0.56, green: 0.45, blue: 1, alpha: 0.9)
            let pink = NSColor(red: 1, green: 0.45, blue: 0.7, alpha: 0.85)
            let faint = accent.withAlphaComponent(0.12)
            let colors = [accent, faint, violet, faint, pink, accent].map(\.cgColor)
            line.colors = colors
            glow.colors = colors
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (gradient, mask) in [(glow, glowMask), (line, lineMask)] {
            gradient.frame = bounds
            mask.frame = bounds
            let inset = mask.lineWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let radius = max(0, min(corner - inset, rect.width / 2, rect.height / 2))
            mask.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        glowMask.shadowPath = glowMask.path?.copy(strokingWithWidth: glowMask.lineWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        CATransaction.commit()
    }

    /// Round it goes, faster while the agent works; still with Reduce Motion.
    private func turn() {
        line.opacity = busy ? 1 : 0.6
        glow.opacity = busy ? 0.55 : 0.28
        for gradient in [line, glow] {
            gradient.removeAnimation(forKey: "turn")
            guard !Motion.reduced else { continue }
            let steps = 48
            let spin = CAKeyframeAnimation(keyPath: "endPoint")
            spin.values = (0...steps).map { step -> NSValue in
                let angle = Double(step) / Double(steps) * 2 * .pi - .pi / 2
                return NSValue(point: NSPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle)))
            }
            spin.duration = busy ? 4 : 9
            spin.repeatCount = .infinity
            spin.calculationMode = .linear
            gradient.add(spin, forKey: "turn")
        }
    }
}

/// What is using Quo, and Stop, in a small pill under the ring's top edge.
private struct AgentPill: View {
    let line: String
    let auto: Bool
    let busy: Bool
    let help: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text(line)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if auto {
                Text("Allowed automatically")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            AgentPillStop()
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(NoticeCard.ground(scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.ink.opacity(scheme == .dark ? 0.16 : 0.1), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.14), radius: 14, y: 4)
        .fixedSize()
        .padding(.top, 8)
        .help(help + ". Stop disconnects it; its tabs stay.")
        .accessibilityElement(children: .contain)
    }
}

private struct AgentPillStop: View {
    @State private var hovering = false

    var body: some View {
        Button { AgentControl.shared.stopSession() } label: {
            Text("Stop")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ground)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Palette.ink.opacity(hovering ? 1 : 0.88), in: Capsule())
                .contentShape(Capsule())
                .background(ClickSpot { AgentControl.shared.stopButton = $0 })
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help("Disconnect it. Its tabs stay where they are.")
    }
}

/// The agent's pointer: the Mac's own arrow with the agent's name beside
/// it, as a second person's pointer is shown in a shared document. Each
/// click it glides from where it last was to where it clicks (the click
/// waits for it, AgentControl.pointerTravel), and a ring of the ring's light
/// spreads from the spot. Still for a few seconds, it fades; the next click
/// brings it back where it was. With Reduce Motion it appears where it
/// clicks, without travelling.
private struct AgentPointerView: View {
    let client: String
    let pointer: AgentControl.AgentPointer?
    let pages: () -> [Tab.ID: CGRect]

    @State private var spot: CGPoint?
    @State private var ripple: UUID?
    @State private var rippling = false
    @State private var shown = false
    @State private var rest: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let spot {
                // The ripple, at the tip.
                Circle()
                    .strokeBorder(AngularGradient(colors: AgentRing.colors, center: .center), lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .scaleEffect(rippling ? 1.4 : 0.3)
                    .opacity(rippling ? 0 : 0.95)
                    .position(spot)
                    .id(ripple)
                HStack(alignment: .top, spacing: 2) {
                    Image(nsImage: NSCursor.arrow.image)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    Text(client)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.accentColor, in: Capsule())
                        .padding(.top, 14)
                }
                // The arrow's tip is the image's hot spot.
                .offset(x: spot.x - NSCursor.arrow.hotSpot.x, y: spot.y - NSCursor.arrow.hotSpot.y)
                .opacity(shown ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pointer) { _, pointer in land(pointer) }
        .onAppear { land(pointer) }
    }

    private func land(_ pointer: AgentControl.AgentPointer?) {
        guard let pointer, let page = pages()[pointer.tab] else {
            withAnimation(Motion.quick) { shown = false }
            return
        }
        let to = CGPoint(x: page.minX + pointer.at.x, y: page.minY + pointer.at.y)
        let travel = Motion.reduced || spot == nil ? nil : Animation.easeInOut(duration: AgentControl.pointerTravel)
        // From the middle of the page the first time, so it's seen arriving.
        if spot == nil, !Motion.reduced { spot = CGPoint(x: page.midX, y: page.midY) }
        withAnimation(.easeOut(duration: 0.12)) { shown = true }
        withAnimation(travel ?? .easeInOut(duration: Motion.reduced ? 0 : AgentControl.pointerTravel)) { spot = to }
        // The ripple once it's there, as the click lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.reduced ? 0 : AgentControl.pointerTravel)) {
            rippling = false
            ripple = pointer.id
            withAnimation(.easeOut(duration: 0.55)) { rippling = true }
        }
        rest?.cancel()
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.4)) { shown = false } }
        rest = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}

/// The ring, its pill and a pointer mid-click, drawn as an agent at work
/// would have them, for the bench's `agentring` picture (no agent needed).
struct AgentRingPicture: View {
    let client: String
    let corner: CGFloat
    let at: CGPoint

    var body: some View {
        ZStack(alignment: .top) {
            AgentGlow(corner: corner, busy: true, still: true)
            AgentPill(line: "\(client) is using \(Store.name)", auto: true, busy: true, help: client)
            ZStack(alignment: .topLeading) {
                Circle()
                    .strokeBorder(AngularGradient(colors: AgentRing.colors, center: .center), lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .scaleEffect(0.9).opacity(0.7)
                    .position(at)
                HStack(alignment: .top, spacing: 2) {
                    Image(nsImage: NSCursor.arrow.image)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    Text(client)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.accentColor, in: Capsule())
                        .padding(.top, 14)
                }
                .offset(x: at.x - NSCursor.arrow.hotSpot.x, y: at.y - NSCursor.arrow.hotSpot.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
