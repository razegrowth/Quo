import LocalAuthentication
import SwiftUI

/// Incognito tabs locked when you leave Quo, opened again with Face ID (or
/// Touch ID, or the passcode), as Safari and Chrome do. While Quo is on its
/// way out they're covered too, so the app switcher's picture of Quo
/// doesn't show them.
@MainActor
final class IncognitoLock: ObservableObject {
    static let shared = IncognitoLock()

    /// Locked: an incognito page shows the lock in its place.
    @Published private(set) var locked = false
    /// Quo going to the background, or a system sheet over it: covered,
    /// not yet locked.
    @Published private(set) var covered = false
    private var unlocking = false
    /// Face ID asked for once on coming back, not again after a Cancel.
    private var askOnReturn = false

    /// Hidden now, whichever the reason.
    var hiding: Bool { locked || covered }

    private var on: Bool { AppSettings.shared.lockIncognito && IncognitoLock.available }

    /// The phone has Face ID, Touch ID or at least a passcode to ask for.
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// What the phone asks with, for the words on the button.
    static var method: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    // MARK: - Quo coming and going

    func leaving() {
        // Face ID's own prompt makes Quo inactive; that's not leaving.
        guard on, !unlocking, !Tabs.shared.incognito.isEmpty else { return }
        covered = true
    }

    func left() {
        guard on, !Tabs.shared.incognito.isEmpty else { return }
        locked = true
        covered = false
        askOnReturn = true
    }

    func back() {
        covered = false
        if Tabs.shared.incognito.isEmpty { locked = false }
        // Straight to Face ID on coming back to an incognito tab, as Safari does.
        if askOnReturn {
            askOnReturn = false
            if locked, Tabs.shared.current?.incognito == true, Browser.shared.panel != .switcher {
                Task { await unlock() }
            }
        }
    }

    /// No incognito tabs left, nothing to keep locked.
    func tabsChanged() {
        if Tabs.shared.incognito.isEmpty { locked = false; covered = false }
    }

    // MARK: - opening

    @discardableResult
    func unlock() async -> Bool {
        guard locked else { return true }
        unlocking = true
        defer { unlocking = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Unlock your Incognito tabs")) ?? false
        if ok {
            Haptics.done()
            withAnimation(Q.quick) { locked = false }
        }
        return ok
    }
}

/// In place of an incognito page while it's locked: what it is, and the
/// way back in, or out to your other tabs.
struct IncognitoLockCover: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var lock = IncognitoLock.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "eyeglasses")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
            Text("Incognito tabs are locked")
                .font(Q.title)
                .titleTracking()
                .foregroundStyle(.white)
                .padding(.top, 18)
            Text("Unlock to see them again.")
                .font(Q.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 6)
            Spacer()
            if lock.locked {
                VStack(spacing: 10) {
                    Button { Task { await lock.unlock() } } label: {
                        Text("Unlock with \(IncognitoLock.method)")
                            .font(Q.bodyEmphasis)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("incognito.unlock")
                    Button { browser.showSwitcher() } label: {
                        Text("See other tabs")
                            .font(Q.bodyEmphasis)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("incognito.others")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
