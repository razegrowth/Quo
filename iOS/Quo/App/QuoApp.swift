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
                    }
                }
                .onAppear {
                    if !settings.onboarded && ProcessInfo.processInfo.environment["QUO_SKIP_ONBOARDING"] == nil {
                        onboarding = true
                    }
                }
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active:
                Tabs.shared.archiveInactive()
                MacSync.shared.pass()
            case .background:
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
            Blocker.shared.start()
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

/// The first launch: the mark rising out of the dark, then three short
/// cards, as the Mac's onboarding opens.
struct OnboardingView: View {
    let done: () -> Void
    @State private var page = 0
    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cards: [(String, String, String)] = [
        ("Quo for iPhone", "A quiet browser that keeps up with Quo on your Mac.", "sparkle"),
        ("Your Mac, here", "Your spaces, pins and bookmarks come through your own iCloud, end to end encrypted. Pin something here and it\u{2019}s on your Mac too.", "desktopcomputer"),
        ("Quiet pages", "Ads, trackers and cookie banners are blocked before they load. Turn any of it off for a site from its toolbar.", "hand.raised"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.white.opacity(bloomed ? 0.10 : 0), .clear], center: .center, startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
                .offset(y: -140)
            VStack(spacing: 0) {
                Spacer()
                Image("QMark")
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color(white: 0.93))
                    .scaleEffect(bloomed ? 1 : 0.5)
                    .blur(radius: bloomed ? 0 : 20)
                    .opacity(bloomed ? 1 : 0)
                Spacer().frame(height: 44)
                TabView(selection: $page) {
                    ForEach(cards.indices, id: \.self) { index in
                        card(cards[index]).tag(index).padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 230)
                .opacity(bloomed ? 1 : 0)
                .offset(y: bloomed ? 0 : 14)
                HStack(spacing: 6) {
                    ForEach(cards.indices, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(index == page ? 0.9 : 0.25))
                            .frame(width: index == page ? 18 : 6, height: 6)
                    }
                }
                .animation(Q.snap, value: page)
                .padding(.top, 8)
                Spacer()
                Button {
                    if page < cards.count - 1 { withAnimation(Q.snap) { page += 1 } } else { done() }
                } label: {
                    Text(page < cards.count - 1 ? "Next" : "Start Browsing")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(white: 0.96), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 24)
                .opacity(bloomed ? 1 : 0)
                .accessibilityIdentifier("onboarding.next")
                Button("Skip", action: done)
                    .font(Q.body)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(height: 44)
                    .padding(.top, 6)
                    .opacity(bloomed && page < cards.count - 1 ? 1 : 0)
            }
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.86).delay(0.15)) { bloomed = true }
        }
    }

    private func card(_ card: (String, String, String)) -> some View {
        VStack(spacing: 12) {
            Image(systemName: card.2)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
            Text(card.0)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(card.1)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Q.radiusXL, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(RoundedRectangle(cornerRadius: Q.radiusXL, style: .continuous).fill(Color.white.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: Q.radiusXL, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)))
        )
    }
}
