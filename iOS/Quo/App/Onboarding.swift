import SwiftUI

/// The first launch: Quo's one long moment. Dark, then the Q blooming out
/// of it in a soft light with one fine ring spreading away; it rises to the
/// top and three scenes follow, each a small living picture of what Quo
/// does, the words sliding at their own pace as you swipe. Done, the whole
/// thing opens from the button outward onto the browser behind it.
struct OnboardingView: View {
    let done: () -> Void

    private enum Stage { case dark, bloom, open }
    @State private var stage: Stage = .dark
    @State private var page: Int? = 0
    @State private var leaving = false
    @State private var reveal: CGFloat = 0
    /// The window's safe area, read from outside the part that ignores it.
    @State private var windowInsets = EdgeInsets()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Scene: Identifiable {
        let id: Int
        let title: String
        let words: String
    }

    private let scenes = [
        Scene(id: 0, title: "Quiet pages.",
              words: "Ads, trackers and cookie banners are gone before they load. The page is all that\u{2019}s left."),
        Scene(id: 1, title: "Your Mac, in your pocket.",
              words: "Your spaces, pins and open tabs from Quo on your Mac, through your own iCloud, end to end encrypted."),
        Scene(id: 2, title: "All under one thumb.",
              words: "Drag the tab card up to hop back a tab. Pull the bar up to search. Pull a page down to load it again."),
    ]

    private var current: Int { page ?? 0 }
    private var last: Bool { current == scenes.count - 1 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // All four sides: an iPhone Duo's outer screen keeps its camera
            // and status in a column down one side.
            let insets = windowInsets
            let button = CGPoint(x: size.width / 2, y: size.height - insets.bottom - 40)
            ZStack {
                Backdrop(lit: stage != .dark, page: current)

                // The bloom: a soft light behind the mark and one fine ring
                // spreading away from it, once.
                Bloom(go: stage != .dark, reduceMotion: reduceMotion)
                    .position(x: size.width / 2, y: size.height * 0.42)

                mark(in: size, insets: insets)

                if stage == .open {
                    pages(size: size, insets: insets)
                        .transition(.opacity)
                }
            }
            // Leaving: the browser shows through a circle opening from the
            // button, as the scene behind it rushes past.
            .scaleEffect(leaving ? 1.12 : 1)
            .blur(radius: leaving ? 6 : 0)
            .mask {
                if leaving {
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: reveal * 2, height: reveal * 2)
                            .position(button)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
                } else {
                    Rectangle().ignoresSafeArea()
                }
            }
            .onChange(of: leaving) { _, on in
                guard on else { return }
                let far = hypot(max(button.x, size.width - button.x), max(button.y, size.height + insets.top + insets.bottom - button.y))
                withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: reduceMotion ? 0.25 : 0.7)) { reveal = far * 1.05 }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { windowInsets = $0 }
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .sensoryFeedback(.selection, trigger: current)
        .task { await open() }
    }

    // MARK: - the opening

    private func open() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { stage = .open }
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.9, dampingFraction: 0.82)) { stage = .bloom }
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { stage = .open }
    }

    private func finish() {
        guard !leaving else { return }
        Haptics.settle()
        // The browser underneath, dark until now, is what the circle opens onto.
        Browser.shared.awaitingOnboarding = false
        withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: reduceMotion ? 0.25 : 0.7)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 0.68)) {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { done() }
        }
    }

    // MARK: - the mark

    /// Large and alone in the middle while it blooms; then up to the top,
    /// small, where it stays over the scenes.
    private func mark(in size: CGSize, insets: EdgeInsets) -> some View {
        let opened = stage == .open
        let side: CGFloat = opened ? 30 : 128
        return Image("QMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .foregroundStyle(Color(white: 0.93))
            .scaleEffect(stage == .dark ? 0.5 : 1)
            .blur(radius: stage == .dark ? 20 : 0)
            .opacity(stage == .dark ? 0 : 1)
            .position(x: size.width / 2, y: opened ? insets.top + 24 : size.height * 0.42)
    }

    // MARK: - the scenes

    private func pages(size: CGSize, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: finish)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 44)
                    .padding(.horizontal, 20)
                    .opacity(last ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: last)
                    .accessibilityIdentifier("onboarding.skip")
            }
            .padding(.top, insets.top + 2)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(scenes) { scene in
                        sceneView(scene, size: size)
                            .containerRelativeFrame(.horizontal)
                            .id(scene.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)

            dots
                .padding(.bottom, 22)

            Button {
                if last {
                    finish()
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { page = current + 1 }
                }
            } label: {
                ZStack {
                    Text("Continue").opacity(last ? 0 : 1)
                    Text("Start Browsing").opacity(last ? 1 : 0)
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(white: 0.96), in: Capsule())
                .animation(.easeOut(duration: 0.2), value: last)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 24)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .padding(.bottom, insets.bottom + 12)
            .accessibilityIdentifier("onboarding.next")
            .rising(stage == .open, delay: 0.6)
        }
    }

    private func sceneView(_ scene: Scene, size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            Group {
                switch scene.id {
                case 0: QuietScene(reduceMotion: reduceMotion)
                case 1: SyncScene(reduceMotion: reduceMotion)
                default: ThumbScene(reduceMotion: reduceMotion)
                }
            }
            .frame(width: 300, height: min(330, size.height * 0.4))
            // Coming in from the side, the picture grows out of a soft
            // blur; going, it falls back into one.
            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content
                    .scaleEffect(1 - abs(phase.value) * 0.22)
                    .blur(radius: abs(phase.value) * 14)
                    .opacity(1 - abs(phase.value) * 0.7)
                    .offset(x: phase.value * -60)
            }
            .rising(stage == .open, delay: 0.42)
            Spacer(minLength: 24)
            VStack(spacing: 14) {
                Text(scene.title)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.9)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content.offset(x: phase.value * 90).opacity(1 - abs(phase.value) * 0.9)
                    }
                Text(scene.words)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content.offset(x: phase.value * 150).opacity(1 - abs(phase.value) * 1.2)
                    }
            }
            .padding(.horizontal, 28)
            .rising(stage == .open, delay: 0.5)
            Spacer(minLength: 20)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(scenes) { scene in
                Capsule()
                    .fill(.white.opacity(scene.id == current ? 0.92 : 0.22))
                    .frame(width: scene.id == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 1), value: current)
        .rising(stage == .open, delay: 0.56)
    }
}

// MARK: - around the scenes

/// The dark stage: greys moving slowly under it, a little lighter behind
/// the middle, a little different for each scene.
private struct Backdrop: View {
    let lit: Bool
    let page: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let glow = lit ? 1.0 : 0
            let shift = Double(page)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, Float(0.45 + 0.08 * sin(t * 0.31))],
                    [Float(0.5 + 0.14 * cos(t * 0.23 + shift)), Float(0.42 + 0.1 * sin(t * 0.29 + shift))],
                    [1, Float(0.52 + 0.08 * cos(t * 0.27))],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(white: 0.02), Color(white: 0.06 * glow), Color(white: 0.02),
                    Color(white: 0.05 * glow), Color(white: (0.15 + 0.02 * shift) * glow), Color(white: 0.04 * glow),
                    Color(white: 0.0), Color(white: 0.04 * glow), Color(white: 0.0),
                ],
                smoothsColors: true
            )
            .animation(.easeOut(duration: 1.2), value: lit)
            .animation(.smooth(duration: 0.8), value: page)
        }
        .background(.black)
        .ignoresSafeArea()
    }
}

/// A soft light swelling behind the mark, and one fine ring spreading
/// away from it and fading.
private struct Bloom: View {
    let go: Bool
    let reduceMotion: Bool
    @State private var spread = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .scaleEffect(go ? 1 : 0.4)
                .opacity(go ? 1 : 0)
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 120, height: 120)
                .scaleEffect(spread ? 6 : 1)
                .opacity(spread ? 0 : (go ? 0.6 : 0))
        }
        .allowsHitTesting(false)
        .onChange(of: go) { _, on in
            guard on, !reduceMotion else { return }
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 2.2)) { spread = true }
        }
    }
}

private extension View {
    /// Rising in: from a little below, soft, to sharp and in place.
    func rising(_ shown: Bool, delay: Double) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 8)
            .animation(.spring(response: 0.7, dampingFraction: 0.88).delay(delay), value: shown)
    }
}

/// A scene's own loop: steps a little apart, round and round, while it's
/// on screen; still with Reduce Motion.
private struct Loop: ViewModifier {
    let steps: Int
    let beats: [Double]
    let reduceMotion: Bool
    @Binding var step: Int

    func body(content: Content) -> some View {
        content.task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                for (index, beat) in beats.enumerated() {
                    try? await Task.sleep(for: .seconds(beat))
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) { step = (index + 1) % steps }
                }
            }
        }
    }
}

/// Glass, as the Mac's onboarding cards: dark, a little light through it,
/// a fine edge brighter at the top.
private struct Glass: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)))
            )
    }
}

/// A line of a page's text, as a grey bar.
private struct Bar: View {
    var width: CGFloat
    var shade = 0.82
    var height: CGFloat = 7
    var body: some View {
        Capsule().fill(Color(white: shade)).frame(width: width, height: height)
    }
}

// MARK: - quiet pages

/// A page with two ads and a cookie banner; they fall away, the words
/// close up over where they were, and the count of what was blocked pops in.
private struct QuietScene: View {
    let reduceMotion: Bool
    @State private var step = 0

    var body: some View {
        let clean = step == 1
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(Color(white: 0.75)).frame(width: 12, height: 12)
                    Bar(width: 60, shade: 0.7)
                    Spacer()
                    Bar(width: 22, shade: 0.85)
                }
                .padding(.bottom, 4)
                Bar(width: 170, shade: 0.25, height: 12)
                Bar(width: 120, shade: 0.25, height: 12)
                ad(clean)
                Bar(width: 190)
                Bar(width: 176)
                Bar(width: 186)
                ad(clean, tall: false)
                Bar(width: 150)
                Bar(width: 182)
                // Room for the cookie banner, while there is one.
                Color.clear.frame(height: clean ? 6 : 64)
            }
            .padding(18)
            .frame(width: 228, alignment: .top)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .bottom) {
                // The cookie banner, sliding away.
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Bar(width: 90, shade: 0.55, height: 6)
                        Bar(width: 64, shade: 0.55, height: 6)
                    }
                    Spacer()
                    Text("Accept all")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Color(white: 0.15), in: Capsule())
                }
                .padding(12)
                .background(Color(white: 0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(8)
                .offset(y: clean ? 90 : 0)
                .opacity(clean ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

            Text("3 blocked")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .scaleEffect(clean ? 1 : 0.6)
                .opacity(clean ? 1 : 0)
                .blur(radius: clean ? 0 : 6)
                .offset(x: 26, y: -14)
        }
        .modifier(Loop(steps: 2, beats: [1.3, 2.4], reduceMotion: reduceMotion, step: $step))
    }

    private func ad(_ gone: Bool, tall: Bool = true) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(white: 0.8))
            .overlay(alignment: .topLeading) {
                Text("Ad")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(6)
            }
            .frame(height: gone ? 0 : (tall ? 62 : 40))
            .scaleEffect(gone ? 0.85 : 1)
            .blur(radius: gone ? 6 : 0)
            .opacity(gone ? 0 : 1)
            .padding(.vertical, gone ? -4.5 : 0)
    }
}

// MARK: - your Mac, in your pocket

/// Quo on a Mac, its sidebar of tabs; three of them lift off and fly over
/// to the phone in front, one after another, landing in its list.
private struct SyncScene: View {
    let reduceMotion: Bool
    @State private var step = 0

    var body: some View {
        let over = step == 1
        ZStack {
            // The Mac's window, behind.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 6, height: 6) }
                    }
                    .padding(.bottom, 6)
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.4)).frame(width: 10, height: 10)
                            Bar(width: CGFloat([46, 38, 52, 30, 42][row]), shade: 0.6, height: 5)
                        }
                        .opacity(row < 3 && over ? 0.35 : 1)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(width: 92)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.8))
                        .frame(height: 52)
                    Bar(width: 96, shade: 0.3, height: 7)
                    Bar(width: 130, shade: 0.75, height: 4)
                    Bar(width: 118, shade: 0.75, height: 4)
                    Bar(width: 124, shade: 0.75, height: 4)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(8)
            }
            .frame(width: 270, height: 170)
            .modifier(Glass(radius: 16))
            .offset(x: -14, y: -62)

            // The phone, in front.
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(.white.opacity(0.3)).frame(width: 30, height: 5).frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                Bar(width: 44, shade: 0.7, height: 6)
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.85)).frame(width: 12, height: 12)
                        Bar(width: CGFloat([46, 38, 52][row]), shade: 0.75, height: 5)
                    }
                    .opacity(over ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.9).delay(0.35 + Double(row) * 0.12), value: over)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 112, height: 210)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
            .offset(x: 92, y: 62)

            // The tabs on their way over.
            ForEach(0..<3, id: \.self) { row in
                let from = CGPoint(x: -126, y: -90 + CGFloat(row) * 18)
                let to = CGPoint(x: 70, y: 34 + CGFloat(row) * 21)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 12, height: 12)
                    Bar(width: CGFloat([46, 38, 52][row]), shade: 0.9, height: 5)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .scaleEffect(over ? 1 : 0.9)
                // Across slower than down, so each one curves over rather
                // than cutting straight across.
                .offset(x: over ? to.x : from.x)
                .animation(.spring(response: 0.85, dampingFraction: 0.9).delay(Double(row) * 0.12), value: over)
                .offset(y: over ? to.y : from.y)
                .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(Double(row) * 0.12), value: over)
                .opacity(over ? 0 : 1)
                .animation(.easeOut(duration: 0.25).delay(0.55 + Double(row) * 0.12), value: over)
            }
        }
        .modifier(Loop(steps: 2, beats: [1.0, 2.6], reduceMotion: reduceMotion, step: $step))
    }
}

// MARK: - all under one thumb

/// A phone and its bar: a thumb on the tab card draws the tab before out
/// and up, the page stepping back behind it; let go, it fills the screen.
private struct ThumbScene: View {
    let reduceMotion: Bool
    @State private var step = 0

    var body: some View {
        // 0 at rest, 1 the thumb down, 2 the card drawn up, 3 landed.
        let thumbDown = step == 1 || step == 2
        let drawn = step == 2
        let landed = step == 3
        ZStack {
            // The phone.
            ZStack(alignment: .bottom) {
                page(shade: 0.99, accent: 0.82)
                    .scaleEffect(drawn ? 0.92 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: drawn ? 18 : 0, style: .continuous))
                    .opacity(landed ? 0 : 1)

                // The tab before, coming out of its button.
                page(shade: 0.93, accent: 0.35)
                    .frame(width: landed ? 188 : (drawn ? 92 : 16), height: landed ? 380 : (drawn ? 180 : 22))
                    .clipShape(RoundedRectangle(cornerRadius: landed ? 0 : (drawn ? 12 : 4), style: .continuous))
                    .shadow(color: .black.opacity(drawn ? 0.35 : 0), radius: 14, y: 8)
                    .rotationEffect(.degrees(landed || drawn ? 0 : 6))
                    .offset(x: landed ? 0 : (drawn ? -24 : -66), y: landed ? 0 : (drawn ? -150 : -16))
                    .opacity(step == 0 ? 0 : 1)

                // The bar.
                HStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(white: 0.75))
                        .frame(width: 16, height: 22)
                        .rotationEffect(.degrees(6))
                        .opacity(step == 0 || landed ? 1 : 0)
                    Spacer()
                    Capsule().fill(Color(white: 0.88)).frame(width: 44, height: 24)
                        .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.2)))
                    Spacer()
                    Circle().fill(Color(white: 0.88)).frame(width: 24, height: 24)
                        .overlay(Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(white: 0.2)))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
            }
            .frame(width: 188, height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(6)
            .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
            .environment(\.colorScheme, .light)
            .scaleEffect(0.86)

            // The thumb.
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .scaleEffect(thumbDown ? 1 : 1.3)
                .opacity(thumbDown ? 0.9 : 0)
                .offset(x: drawn ? -20 : -57, y: drawn ? 40 : 140)
        }
        .modifier(Loop(steps: 4, beats: [1.1, 0.5, 0.9, 1.8], reduceMotion: reduceMotion, step: $step))
    }

    /// A page: a header, a picture and lines of words.
    private func page(shade: Double, accent: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: accent))
                .frame(height: 74)
            Bar(width: 120, shade: 0.3, height: 9)
            Bar(width: 90, shade: 0.3, height: 9)
            Bar(width: 140, shade: 0.75, height: 5)
            Bar(width: 128, shade: 0.75, height: 5)
            Bar(width: 136, shade: 0.75, height: 5)
            Bar(width: 100, shade: 0.75, height: 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: shade))
    }
}
