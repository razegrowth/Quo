import SwiftUI
import UIKit

@main
struct QuoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var settings = AppSettings.shared
    @State private var onboarding = false

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .tint(Q.ink)
                .onOpenURL { url in open(url) }
                .fullScreenCover(isPresented: $onboarding) {
                    OnboardingView {
                        settings.onboarded = true
                        onboarding = false
                        // Then the search, once the onboarding has gone.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { Browser.shared.searchIfEmpty() }
                    }
                }
                .onAppear {
                    if !settings.onboarded && ProcessInfo.processInfo.environment["QUO_SKIP_ONBOARDING"] == nil {
                        // There at once, dark, not sliding up over the browser:
                        // the cover's own animation is switched off for it.
                        UIView.setAnimationsEnabled(false)
                        onboarding = true
                        DispatchQueue.main.async { UIView.setAnimationsEnabled(true) }
                    }
                }
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active:
                IncognitoLock.shared.back()
                Tabs.shared.archiveInactive()
                MacSync.shared.pass()
            case .inactive:
                IncognitoLock.shared.leaving()
            case .background:
                IncognitoLock.shared.left()
                Tabs.shared.saveDeep()
                MacSync.shared.handOff()
                Task { await Tabs.shared.current?.snapshot() }
            default: break
            }
        }
    }

    private func open(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            Browser.shared.go(url, newTab: true)
        } else if scheme == "quo", let rest = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value, let target = URL(string: rest) {
            Browser.shared.go(target, newTab: true)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            FrameMeter.shared.start()
            KeyboardWarmup.run()
            Haptics.prepare()
            Blocker.shared.start()
            Media.start()
            MacSync.shared.onArrived = { Browser.shared.arrived($0) }
            MacSync.shared.start()
            Tabs.shared.archiveInactive()
        }
        return true
    }

    /// iCloud's silent push: the Mac wrote.
    func application(_ application: UIApplication, didReceiveRemoteNotification info: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await MainActor.run { MacSync.shared.pass() }
        return .newData
    }
}

/// The first keyboard after launch takes a third of a second to come up,
/// which showed as the search sheet stopping halfway on the first +. A
/// field off screen takes focus and gives it back at launch, so the
/// keyboard is loaded before anyone asks for it; it never shows.
@MainActor
enum KeyboardWarmup {
    static func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first,
                  window.rootViewController?.presentedViewController == nil else { return }
            let field = UITextField(frame: CGRect(x: -1000, y: -1000, width: 10, height: 10))
            field.autocorrectionType = .no
            window.addSubview(field)
            UIView.performWithoutAnimation {
                field.becomeFirstResponder()
                field.resignFirstResponder()
            }
            field.removeFromSuperview()
        }
    }
}
