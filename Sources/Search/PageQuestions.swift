import SwiftUI

/// The same site permission question in a browser or a small popup window.
struct CaptureQuestion: View {
    @ObservedObject var browser: Browser
    let ask: Browser.CaptureAsk

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { question; actions }.fixedSize()
            VStack(alignment: .leading, spacing: 10) {
                question
                ViewThatFits(in: .horizontal) {
                    actions.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { buttons }
                }
                .padding(.leading, 42)
            }
        }
        .noticeCard()
    }

    private var question: some View {
        HStack(spacing: 12) {
            NoticeIcon(symbol: ask.wants == "location" ? "location" : ask.wants == "microphone" ? "mic" : ask.wants == "notifications" ? "bell"
                  : ask.wants == "cookies" ? "person.crop.circle" : "video")
            NoticeText(ask.wants == "location" ? "\(ask.host) wants to know your location"
                 : ask.wants == "notifications" ? "\(ask.host) wants to send you notifications"
                 // Safari's question, in fewer words: a yes lets the framed
                 // site know you were on this one.
                 : ask.wants == "cookies" ? "\(ask.host) wants to use its cookies and website data on \(ask.under), which also lets it see you were there"
                 : "\(ask.host) wants to use your \(ask.wants)")
        }
    }

    private var actions: some View {
        HStack(spacing: 4) { buttons }
    }

    @ViewBuilder
    private var buttons: some View {
        NoticeButton("Don't allow") { browser.denyCapture() }
        if ask.once, ask.keeps {
            NoticeButton("Always allow") { browser.allowCapture() }
        }
        NoticeButton(ask.once ? "Allow once" : "Allow", filled: true) {
            ask.once ? browser.allowCaptureOnce() : browser.allowCapture()
        }
    }
}

/// A page asking to share the screen (Browser.askedToShareScreen): nothing
/// is shared until a screen or a window is picked in macOS's own picker,
/// which only these two answers open.
struct ScreenQuestion: View {
    @ObservedObject var browser: Browser
    let ask: Browser.CaptureAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
                Text(ask.sound ? "\(ask.host) wants to share your screen and your Mac's sound"
                               : "\(ask.host) wants to share your screen")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button { browser.denyShare() } label: {
                    Text("Don't allow")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                Spacer(minLength: 8)
                // A window gives away less than a whole screen: it is the
                // one drawn as the answer.
                Button { browser.shareScreen() } label: {
                    Text("Share a Screen")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                Button { browser.shareWindow() } label: {
                    Text("Share a Window")
                        .foregroundStyle(Palette.ground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Palette.ink, in: Capsule())
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink)
            .buttonStyle(PressStyle())
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(18)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        .padding(.horizontal, 16)
    }
}

/// A password offer remains readable in the popup that submitted the form.
/// In the notice card (Notices.swift), with a key beside it: as a small
/// grey capsule it went by unseen.
struct PasswordOffer: View {
    @ObservedObject var browser: Browser
    let offer: Browser.Offer

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { question; actions }.fixedSize()
            VStack(alignment: .leading, spacing: 10) {
                question
                ViewThatFits(in: .horizontal) {
                    actions.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { buttons }
                }
                .padding(.leading, 42)
            }
        }
        .noticeCard()
    }

    private var question: some View {
        let login = offer.login
        return HStack(spacing: 12) {
            NoticeIcon(symbol: "key")
            NoticeText(offer.changed
                ? "Update the password for \(login.user) on \(login.host)?"
                : (login.user.isEmpty
                    ? "Save this password for \(login.host)?"
                    : "Save the password for \(login.user) on \(login.host)?"))
        }
    }

    private var actions: some View { HStack(spacing: 4) { buttons } }

    @ViewBuilder
    private var buttons: some View {
        if !offer.changed {
            NoticeButton("Never here") { browser.neverOffer() }
        }
        NoticeButton("Not now") { browser.dropOffer() }
        NoticeButton(offer.changed ? "Update" : "Save", filled: true) { browser.keepOffer() }
    }
}
