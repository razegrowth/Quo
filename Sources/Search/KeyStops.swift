import AppKit
import SwiftUI

/// A control Tab reaches whatever the Mac's Keyboard Navigation is set to.
/// Quo draws its own switches and choices, and a drawn control (or a
/// button, with Keyboard Navigation off, as it is out of the box) is not a
/// stop on the way through a window, so Settings couldn't be worked from
/// the keyboard at all. This makes it one: a ring in the accent colour
/// while it has focus, Space and Return press it, and the arrow keys go to
/// `move` (a row of choices steps through them).
struct KeyStop: ViewModifier {
    /// The ring's corners, as the control's own are; nil for a capsule.
    var corner: CGFloat? = 8
    var act: (() -> Void)? = nil
    var move: ((MoveCommandDirection) -> Void)? = nil
    /// Told when focus comes and goes, by key or not.
    var focus: ((Bool) -> Void)? = nil
    @FocusState private var focused: Bool
    /// Focus that came by a key. A click gives a control focus too, and a
    /// ring after every click would be noise, so it shows only for this.
    @State private var byKey = false

    /// Whether what is happening now came from the keyboard.
    @MainActor static var fromKeys: Bool {
        guard let type = NSApp.currentEvent?.type else { return false }
        return type == .keyDown || type == .keyUp
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .overlay { KeyRing(on: focused && byKey, corner: corner) }
            .onKeyPress(keys: [.space, .return]) { _ in
                guard let act else { return .ignored }
                byKey = true
                act()
                return .handled
            }
            .onMoveCommand { direction in
                byKey = true
                move?(direction)
            }
            .onChange(of: focused) { _, on in
                byKey = on && KeyStop.fromKeys
                focus?(on && byKey)
            }
    }
}

/// The ring itself: two points of the accent colour, just outside the
/// control so it doesn't cover what it rings. No fade: it is where the
/// keyboard is, and it should be there the moment the key is pressed.
struct KeyRing: View {
    let on: Bool
    var corner: CGFloat? = 8

    var body: some View {
        Group {
            if let corner {
                RoundedRectangle(cornerRadius: corner + 3, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            } else {
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .padding(-3)
        .opacity(on ? 1 : 0)
        .allowsHitTesting(false)
    }
}

extension View {
    func keyStop(corner: CGFloat? = 8, act: (() -> Void)? = nil,
                 focus: ((Bool) -> Void)? = nil,
                 move: ((MoveCommandDirection) -> Void)? = nil) -> some View {
        modifier(KeyStop(corner: corner, act: act, move: move, focus: focus))
    }
}

extension Array where Element: Equatable {
    /// The one before or after `item` for an arrow key: left and up go
    /// back, right and down go on; nil past either end.
    func step(from item: Element, _ direction: MoveCommandDirection) -> Element? {
        guard let index = firstIndex(of: item) else { return nil }
        let to = direction == .left || direction == .up ? index - 1 : index + 1
        return indices.contains(to) ? self[to] : nil
    }
}

/// A pop-up menu as a stop: AppKit's own takes Tab only with Keyboard
/// Navigation on, so this one is a stop either way, and the arrow keys
/// choose from it without opening it.
struct KeyChoice<Option: Equatable>: ViewModifier {
    @Binding var selection: Option
    let options: [Option]

    func body(content: Content) -> some View {
        content
            .focusable(false)
            .keyStop(corner: 6, move: { direction in
                if let to = options.step(from: selection, direction) { selection = to }
            })
    }
}

extension View {
    func keyChoice<Option: Equatable>(_ selection: Binding<Option>, among options: [Option]) -> some View {
        modifier(KeyChoice(selection: selection, options: options))
    }
}
