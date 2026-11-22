import UIKit

/// Pull the page down from its top to load it again. A small frosted disc
/// with the Q comes down out from under the status bar into the gap the
/// page leaves, a ring drawing itself around it as you pull. Far enough, and you feel it: the ring closes and the disc gives a
/// little pop. Let go then, and it settles over the page's top with the
/// ring running round while the page loads, then closes the ring and
/// shrinks back up out of sight. Let go short, and it simply goes back up
/// with the page.
@MainActor
final class PullRefresh: UIView {
    enum Phase { case idle, pulling, armed, loading, finishing }
    private(set) var phase: Phase = .idle

    static let size: CGFloat = 40
    /// How far to pull for a reload: past the point a thumb would reach by
    /// accident, well short of a long stretch.
    static let reach: CGFloat = 92

    private let disc = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let mark = UIImageView(image: UIImage(named: "QMark")?.withRenderingMode(.alwaysTemplate))
    private var started = Date()

    /// Where the page's top is, under the status bar's strip.
    var top: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        alpha = 0

        disc.frame = bounds
        disc.clipsToBounds = true
        disc.layer.cornerRadius = Self.size / 2
        disc.layer.borderWidth = 0.5
        addSubview(disc)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath

        let circle = UIBezierPath(arcCenter: CGPoint(x: Self.size / 2, y: Self.size / 2), radius: Self.size / 2 - 4,
                                  startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        for shape in [track, ring] {
            shape.frame = bounds
            shape.path = circle
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        ring.strokeEnd = 0

        mark.contentMode = .scaleAspectFit
        mark.bounds = CGRect(x: 0, y: 0, width: 17, height: 17)
        mark.center = CGPoint(x: Self.size / 2, y: Self.size / 2)
        addSubview(mark)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in self.paint() }
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func paint() {
        let ink = UIColor(Q.ink).resolvedColor(with: traitCollection)
        mark.tintColor = ink
        ring.strokeColor = ink.cgColor
        track.strokeColor = ink.withAlphaComponent(0.12).cgColor
        disc.layer.borderColor = UIColor(Q.hairline).resolvedColor(with: traitCollection).cgColor
    }

    /// Where it sits for a pull: in the middle of the gap the page has left,
    /// out of sight under the strip at first, slowing past the reach.
    private func center(for pull: CGFloat) -> CGPoint {
        let eased = pull <= Self.reach ? pull : Self.reach + Fling.rubberBand(pull - Self.reach, dimension: 240)
        return CGPoint(x: superview?.bounds.midX ?? 0, y: top + eased / 2)
    }

    /// Resting over the page's top while it loads.
    private var restingCenter: CGPoint {
        CGPoint(x: superview?.bounds.midX ?? 0, y: top + Self.size / 2 + 12)
    }

    /// The page pulled down this far by a finger (or springing back).
    func pulled(_ pull: CGFloat, dragging: Bool) {
        switch phase {
        case .loading, .finishing:
            return
        case .idle:
            guard dragging, pull > 4 else { return }
            phase = .pulling
            Haptics.prepare()
        case .pulling, .armed:
            break
        }
        let progress = min(1, max(0, pull / Self.reach))
        Motion.still {
            center = center(for: pull)
            alpha = min(1, progress * 2.2)
            let scale = 0.55 + 0.45 * progress
            transform = phase == .armed ? transform : CGAffineTransform(scaleX: scale, y: scale)
            ring.strokeEnd = progress
        }
        if dragging, phase == .pulling, progress >= 1 {
            phase = .armed
            Haptics.tap()
            // The ring closes, and the disc gives: up a touch and back.
            Motion.still { transform = .identity }
            UIView.animate(springDuration: 0.32, bounce: 0.45, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction]) {
                self.transform = CGAffineTransform(scaleX: 1.14, y: 1.14)
            } completion: { _ in
                UIView.animate(springDuration: 0.3, bounce: 0.3) { self.transform = .identity }
            }
        } else if dragging, phase == .armed, progress < 0.85 {
            // Pushed back up before letting go: not this time.
            phase = .pulling
            Motion.still { transform = CGAffineTransform(scaleX: 0.55 + 0.45 * progress, y: 0.55 + 0.45 * progress) }
        } else if !dragging, phase == .pulling, pull <= 1 {
            phase = .idle
            Motion.still { alpha = 0 }
        }
    }

    /// The finger let go: a reload if it was pulled far enough.
    func released() -> Bool {
        guard phase == .armed else { return false }
        phase = .loading
        started = Date()
        Haptics.settle()
        // To rest over the page as it springs back, the ring running round.
        Motion.spring(0.45, bounce: 0.2) {
            self.center = self.restingCenter
            self.transform = .identity
            self.alpha = 1
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        ring.strokeEnd = 0.28
        CATransaction.commit()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 0.8
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
        return true
    }

    /// The page has loaded: the ring closes and the disc goes back up.
    func finished() {
        guard phase == .loading else { return }
        // Long enough to be seen running, never a blink.
        let shown = Date().timeIntervalSince(started)
        if shown < 0.7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 - shown) { [weak self] in self?.finished() }
            return
        }
        phase = .finishing
        let closing = CABasicAnimation(keyPath: "strokeEnd")
        closing.fromValue = ring.presentation()?.strokeEnd ?? ring.strokeEnd
        closing.toValue = 1
        closing.duration = 0.22
        closing.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.strokeEnd = 1
        ring.add(closing, forKey: "close")
        UIView.animate(springDuration: 0.24, bounce: 0.4) {
            self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        } completion: { _ in
            UIView.animate(springDuration: 0.36, bounce: 0) {
                self.center = CGPoint(x: self.center.x, y: self.top - Self.size)
                self.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
                self.alpha = 0
            } completion: { _ in
                self.ring.removeAnimation(forKey: "spin")
                self.ring.strokeEnd = 0
                self.transform = .identity
                self.phase = .idle
            }
        }
    }
}
