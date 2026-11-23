import AppKit
import SwiftUI

// The first time, as Arc and Dia do it: the whole window, a slow living
// light in graphite greys behind frosted cards, as monochrome as the mark,
// each step's words and choices rising in one after another. Six steps,
// every one of them skippable, nothing asked twice:
//
//   1. Welcome: the opening — the window dark, the mark blooming out of it
//      with a burst of light and a ring spreading away, then the stage
//      coming up behind it and the words unfurling under it. Once, the
//      first time the step shows.
//   2. Make it yours: light or dark, where the tabs go, Roomy or Compact,
//      the first space's colour, with a small window that changes as you pick.
//   3. Bring your things: Arc's spaces and pins if Arc is here, or another
//      browser's passwords, bookmarks and history.
//   4. Sync: iCloud, end to end encrypted with no account of ours, or a
//      folder, or not now.
//   5. Fewer ads: the blocker and the lists worth adding, and the default
//      browser.
//   6. All set: the six keys worth knowing.
//
// Always drawn dark, whatever the app is set to: the stage is the same for
// everyone, and the window's own look comes back the moment it is done.
// Under Reduce Motion nothing floats or drifts, and steps cross-fade.

struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var sync = Sync.shared
    @ObservedObject private var lists = FilterLists.shared

    @State private var step = 0
    @State private var forward = true

    // Bringing things over. Nil until one is picked, which means the first.
    @State private var source: ImportSource?
    @State private var wantsPasswords = true
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    /// Each of its profiles into a profile of its own here (see takeProfiles).
    @State private var wantsProfiles = true
    /// Its store extensions, fresh from the Chrome Web Store, each asked about.
    @State private var wantsExtensions = true
    /// What is on this Mac, found once off the main thread: the browsers
    /// there is something to read in, and those macOS keeps from this app.
    @State private var found: [ImportSource]?
    @State private var refused: [Chromium.Unavailable] = []
    @State private var allowTrouble: String?
    /// What each holds, by browser and profile ("" for all of them).
    @State private var previews: [String: ImportSource.Preview] = [:]
    /// Each browser's profiles and the one it used last, read with the rest.
    @State private var profileLists: [String: [ImportSource.Profile]] = [:]
    @State private var usual: [String: String] = [:]
    @State private var bringing = false
    @State private var brought: String?
    /// Arc's spaces and pins, brought over once this is done, straight into
    /// the sidebar it reveals: not by opening Bring Things Over, whose
    /// switches all on and Bring them in read as if nothing had come yet,
    /// and was pressed again.
    @State private var arcAfter = false
    /// The Arc profile those come from: the one read for the rest, or nil
    /// for every one.
    @State private var arcProfile: String?
    /// Arc's spaces and pins asked for, on its row (see bring).
    @State private var wantsArcSpaces = true

    @State private var isDefault = Links.isDefault
    @State private var askedDefault = false

    /// The opening (see welcome): 0 the window dark, 1 the mark lit in it,
    /// 2 the stage up and the words in. Played once; Back to the first
    /// step finds it settled.
    @State private var opening = 2
    /// The light that spreads away from the mark as it lights, and the
    /// glint that crosses it.
    @State private var wave = false
    @State private var glint = false

    static let steps = 6
    private var reduced: Bool { Motion.reduced }

    init(browser: Browser, prefs: Preferences, step: Int = 0) {
        self.browser = browser
        self.prefs = prefs
        _step = State(initialValue: step)
        _opening = State(initialValue: step == 0 && !Motion.reduced ? 0 : 2)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Stage(browser: browser, reduced: reduced)
                .ignoresSafeArea()
                .opacity(opening >= 2 ? 1 : 0)
                .animation(.easeInOut(duration: 1.6), value: opening)

            VStack(spacing: 0) {
                top
                    .opacity(opening >= 2 ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: opening)
                Spacer(minLength: 12)
                ZStack {
                    switch step {
                    case 0: welcome
                    case 1: yours
                    case 2: bring
                    case 3: syncing
                    case 4: protection
                    default: done
                    }
                }
                .frame(maxWidth: step == 1 ? 860 : 640)
                .id(step)
                .transition(reduced ? .opacity : .asymmetric(
                    insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                    removal: .offset(x: forward ? -60 : 60).combined(with: .opacity).combined(with: .scale(scale: 0.98))
                ))
                Spacer(minLength: 12)
                foot
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        // Extensions coming over, from here or anywhere: the same card as
        // the window's, which this covers.
        .overlay(alignment: .bottomTrailing) {
            if #available(macOS 15.4, *) {
                ExtensionImportCard()
                    .padding(.trailing, 24)
                    .padding(.bottom, 96)
            }
        }
        .environment(\.colorScheme, .dark)
        // A first run on a Mac with Apple Intelligence starts with it on:
        // shorter tab names and link summaries (Intelligence.swift). The
        // switch on the blocking step turns both off; skipped, they stay on.
        .onAppear {
            if OnDevice.available, !prefs.welcomed {
                prefs.shortTitles = true
                prefs.summarizesLinks = true
            }
        }
        .animation(reduced ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86), value: step)
        .transition(.opacity)
    }

    // MARK: - around the steps

    /// The steps so far, as a row of short bars; Skip at the far end.
    private var top: some View {
        HStack {
            Spacer().frame(width: 60)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<WelcomePanel.steps, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i <= step ? 0.9 : 0.18))
                        .frame(width: i == step ? 26 : 8, height: 4)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 1), value: step)
            Spacer()
            ZStack(alignment: .trailing) {
                // Held open on the last step too, so the bars stay centred.
                Color.clear
                if step < WelcomePanel.steps - 1 {
                    Button("Skip") { finish() }
                        .buttonStyle(PressStyle())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(width: 60, height: 20)
        }
    }

    private var foot: some View {
        HStack(spacing: 12) {
            if step > 0 && step < WelcomePanel.steps - 1 {
                Ghost("Back") { go(-1) }
            }
            Spacer()
            if step > 0 && step < WelcomePanel.steps - 1 {
                Primary("Continue") { go(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: step == 1 ? 860 : 640)
        .frame(height: 44)
        .opacity(step == 0 || step == WelcomePanel.steps - 1 ? 0 : 1)
    }

    private func go(_ by: Int) {
        forward = by > 0
        step = max(0, min(WelcomePanel.steps - 1, step + by))
    }

    // MARK: - 1. welcome

    private var welcome: some View {
        VStack(spacing: 30) {
            ZStack {
                // The burst of light the mark comes out of, and the ring
                // that spreads away from it: only while it lights.
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.12), .clear],
                                         center: .center, startRadius: 0, endRadius: 220))
                    .frame(width: 440, height: 440)
                    .scaleEffect(opening == 1 ? 1.2 : 0.3)
                    .opacity(opening == 1 ? 1 : 0)
                    .allowsHitTesting(false)
                // A wave of soft light, and a fine ring catching the light
                // as it turns, both spreading away and gone.
                Circle()
                    .fill(RadialGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.45),
                        .init(color: .white.opacity(0.22), location: 0.78),
                        .init(color: .clear, location: 1),
                    ]), center: .center, startRadius: 0, endRadius: 75))
                    .frame(width: 150, height: 150)
                    .scaleEffect(wave ? 4.2 : 0.6)
                    .opacity(wave ? 0 : (opening >= 1 ? 1 : 0))
                    .allowsHitTesting(false)
                Circle()
                    .strokeBorder(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white.opacity(0.1),
                                                           .white.opacity(0.7), .white.opacity(0)], center: .center),
                                  lineWidth: 1.2)
                    .blur(radius: 0.6)
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(wave ? 200 : 0))
                    .scaleEffect(wave ? 6 : 0.8)
                    .opacity(wave ? 0 : (opening >= 1 ? 1 : 0))
                    .allowsHitTesting(false)
                Floating(reduced: reduced) {
                    AppMark(height: 96)
                        // A glint crossing the mark as it lights, in its shape.
                        .overlay {
                            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 46)
                                .rotationEffect(.degrees(18))
                                .offset(x: glint ? 110 : -110)
                                .opacity(glint ? 0 : 1)
                                .blendMode(.plusLighter)
                                .mask(AppMark(height: 96))
                                .allowsHitTesting(false)
                        }
                        .shadow(color: .white.opacity(opening == 1 ? 0.55 : 0.18), radius: opening == 1 ? 60 : 36)
                        .shadow(color: .black.opacity(0.35), radius: 20, y: 14)
                }
                .scaleEffect(opening == 0 ? 0.5 : opening == 1 ? 1.3 : 1)
                .opacity(opening == 0 ? 0 : 1)
                .blur(radius: opening == 0 ? 20 : 0)
            }
            .frame(height: 120)
            if opening >= 2 {
                VStack(spacing: 14) {
                    Text("Welcome to \(Store.name)")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(.white)
                        .modifier(Unfurl())
                    Text("A fast, quiet browser for the Mac, with Arc's habits on the engine already inside it.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 440)
                        .rise(3)
                }
                Primary("Get Started", large: true) { go(1) }
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 8)
                    .rise(5)
            }
        }
        .onAppear(perform: open)
    }

    /// The opening, the first time the first step shows: dark, then the
    /// mark lit with its burst and ring, then the stage and the words, the
    /// mark rising to make room for them.
    private func open() {
        guard opening == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.62)) { opening = 1 }
            withAnimation(.easeOut(duration: 1.9)) { wave = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.8)) { glint = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.84)) { opening = 2 }
        }
    }

    // MARK: - 2. make it yours

    private var yours: some View {
        // The heading over both; the choices and the window beside them,
        // the same height and their tops in line.
        let tall: CGFloat = 256
        return VStack(alignment: .leading, spacing: 24) {
            Heading("Make it yours.", "The window on the right follows along.")
                .rise(0)
            HStack(alignment: .top, spacing: 28) {
                Glass {
                    VStack(alignment: .leading, spacing: 0) {
                        Row("Appearance") {
                            Chips(options: [(Look.light, "Light", "sun.max"), (Look.dark, "Dark", "moon"), (Look.system, "Auto", "circle.lefthalf.filled")],
                                  selection: $prefs.look)
                        }
                        .frame(maxHeight: .infinity)
                        Row("Tabs") {
                            Chips(options: [(TabsLayout.left, "Left", "sidebar.left"), (TabsLayout.right, "Right", "sidebar.right"), (TabsLayout.top, "Top", "rectangle.topthird.inset.filled")],
                                  selection: Binding(get: { prefs.tabsLayout == .icons ? .left : prefs.tabsLayout },
                                                     set: { layout in withAnimation(Motion.glide) { prefs.tabsLayout = layout } }))
                        }
                        .frame(maxHeight: .infinity)
                        Row("Density") {
                            Chips(options: [(true, "Roomy", "rectangle.expand.vertical"), (false, "Compact", "rectangle.compress.vertical")],
                                  selection: Binding(get: { prefs.roomyTabs }, set: { on in withAnimation(Motion.glide) { prefs.roomyTabs = on } }))
                        }
                        .frame(maxHeight: .infinity)
                        Row("Colour") {
                            // A colour is a space's: picked, spaces come on
                            // to wear it, and the stage behind takes it. The
                            // wheel beside them is the whole picker, as the
                            // space's Colour… has it.
                            HStack(spacing: 8) {
                                Swatches(selection: Binding(get: { browser.space.colour },
                                                            set: { colour in
                                                                if colour > 0, !prefs.usesSpaces { prefs.usesSpaces = true }
                                                                browser.setSpaceColour(browser.spaceID, to: colour)
                                                            }))
                                WheelButton(browser: browser, prefs: prefs)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: tall)
                .rise(1)
                MiniWindow(layout: prefs.tabsLayout, roomy: prefs.roomyTabs, look: prefs.look,
                           tint: browser.space.tint)
                    .frame(width: (tall * 1.42).rounded(), height: tall)
                    .rise(2)
            }
        }
    }

    // MARK: - 3. bring your things

    private var bring: some View {
        let sources = found ?? []
        let chosen = source ?? sources.first
        let arcHere = FileManager.default.fileExists(atPath: Arc.file.path)
        let preview = chosen.flatMap { previews[previewKey($0)] }
        return VStack(alignment: .leading, spacing: 20) {
            Heading("Bring your things.", "Nothing in the other browser changes, and nothing leaves your Mac.")
                .rise(0)
            // Arc's spaces and pins are a row of the Arc card below when Arc
            // is one to bring from; only when its data can't be read is
            // this card how they come over.
            if arcHere, !sources.contains(where: { $0.name == "Arc" }) {
                Glass(highlight: true) {
                    HStack(spacing: 16) {
                        Badge(symbol: "square.stack.3d.up.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Coming from Arc?")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Your spaces, pinned tabs and folders, just as you left them.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 8)
                        if arcAfter {
                            Done("Right after this")
                        } else {
                            Primary("Bring Arc Over") { arcAfter = true }
                        }
                    }
                }
                .rise(1)
            }
            if let chosen {
                Glass {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(sources.count > 1 ? "From" : "From \(chosen.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                            if sources.count > 1 {
                                Chips(options: sources.prefix(4).map { ($0, $0.name, nil) },
                                      selection: Binding(get: { chosen }, set: { source = $0; brought = nil; count($0) }))
                            }
                            Spacer()
                        }
                        if chosen.importsPasswords {
                            Toggled("Passwords", counted(preview?.passwords, "Into your Mac's keychain"), on: $wantsPasswords,
                                    empty: preview?.passwords == 0)
                        }
                        Toggled("Bookmarks", counted(preview?.bookmarks, "With their folders"), on: $wantsBookmarks,
                                empty: preview?.bookmarks == 0)
                        Toggled("History", counted(preview?.places, "So the address field knows where you go"), on: $wantsHistory,
                                empty: preview?.places == 0)
                        if arcHere, chosen.name == "Arc" {
                            Toggled("Spaces and pins", "Your spaces, pinned tabs and folders, as you left them", on: $wantsArcSpaces)
                        }
                        if let list = profileLists[chosen.id], list.count > 1 {
                            Toggled("Profiles", "\(list.count) — \(ListFormatter.localizedString(byJoining: list.map(\.name))), each a profile here",
                                    on: Binding(get: { wantsProfiles }, set: { wantsProfiles = $0; brought = nil; count(chosen) }))
                        }
                        let fresh = freshExtensions(preview)
                        if !fresh.isEmpty {
                            Toggled("Extensions", "\(fresh.count) — \(ImportSource.Addon.names(fresh)). You confirm each one",
                                    on: $wantsExtensions)
                        }
                        if let left = preview?.leftBehind, !left.isEmpty {
                            Text(left.allSatisfy(\.lookFor)
                                 ? "\(chosen.name)'s add-ons can't run here: \(ImportSource.Addon.names(left, first: 4)). Look for them in the Chrome Web Store."
                                 : "Can't come over: " + left.prefix(4).map { "\(WelcomePanel.named($0.name)) (\($0.skip ?? ""))" }.joined(separator: ", ")
                                    + (left.count > 4 ? " and \(left.count - 4) more — see Settings › Bring Things Over" : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // What came over at the left; the button at the right,
                        // where the eye ends up after the switches.
                        HStack(spacing: 12) {
                            if let brought {
                                Done(brought)
                                Spacer(minLength: 0)
                            } else {
                                Spacer(minLength: 0)
                                if bringing { ProgressView().controlSize(.small) }
                                Primary(bringing ? "Bringing…" : "Bring Them In") { bringAll(from: chosen) }
                                    .disabled(bringing || !wanted(chosen, preview: preview, fresh: fresh))
                            }
                        }
                        .padding(.top, 4)
                        .animation(Motion.settle, value: brought)
                    }
                }
                .rise(arcHere ? 2 : 1)
            }
            // Here, but kept from this app by macOS: said by name with the
            // way to allow it, never "no other browser". One card for all
            // of them, a button each.
            if !refused.isEmpty {
                let names = ListFormatter.localizedString(byJoining: refused.map(\.source.name))
                Glass {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 16) {
                            Badge(symbol: "lock.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(names) \(refused.count == 1 ? "is" : "are") on this Mac too")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("macOS keeps \(refused.count == 1 ? "its" : "their") data from other apps until you allow \(Store.name) to read it.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(refused.indices, id: \.self) { index in
                                Ghost("Allow \(refused[index].source.name)…") { allow(refused[index].source) }
                            }
                        }
                        .padding(.leading, 60)
                        if let allowTrouble {
                            Text(allowTrouble)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 60)
                        }
                    }
                }
                .rise(arcHere || chosen != nil ? 3 : 1)
            }
            if found != nil, chosen == nil, refused.isEmpty, !arcHere {
                Glass {
                    Text("No other browser found on this Mac, so there's nothing to bring. You can always bring a file another browser exported, from File › Bring Things Over.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .rise(1)
            }
        }
        .animation(Motion.settle, value: source)
        .animation(Motion.settle, value: previews.count)
        .animation(Motion.settle, value: refused.count)
        .onAppear { if found == nil { look() } }
    }

    /// Something there is to bring: a switch on over something found, or
    /// still being counted.
    private func wanted(_ source: ImportSource, preview: ImportSource.Preview?, fresh: [ImportSource.Addon]) -> Bool {
        (source.name == "Arc" && wantsArcSpaces && FileManager.default.fileExists(atPath: Arc.file.path))
            || (source.importsPasswords && wantsPasswords && preview?.passwords != 0)
            || (wantsBookmarks && preview?.bookmarks != 0)
            || (wantsHistory && preview?.places != 0)
            || (wantsExtensions && !fresh.isEmpty)
    }

    /// An extension's name as it should read: one loaded from a folder
    /// without a name of its own has only its id, which says nothing.
    static func named(_ name: String) -> String {
        name.range(of: "^[a-p]{32}$", options: .regularExpression) != nil ? "An unnamed extension" : name
    }

    /// "312 — Folders and all", or the words alone while counting.
    private func counted(_ n: Int?, _ detail: String) -> String {
        guard let n else { return detail }
        return n == 0 ? "Nothing to bring" : "\(n.formatted()) — \(detail)"
    }

    /// Every profile, each into its own, or the one used most recently.
    private func eachProfile(_ source: ImportSource) -> Bool {
        wantsProfiles && (profileLists[source.id]?.count ?? 0) > 1
    }

    /// The profile read: nil for every one.
    private func profile(of source: ImportSource) -> String? {
        eachProfile(source) ? nil : usual[source.id]
    }

    private func previewKey(_ source: ImportSource) -> String {
        "\(source.id)/\(profile(of: source) ?? "")"
    }

    private func freshExtensions(_ preview: ImportSource.Preview?) -> [ImportSource.Addon] {
        guard #available(macOS 15.4, *), let preview else { return [] }
        return ExtensionImport.fresh(preview.addons)
    }

    /// The browsers on this Mac, found off the main thread, and the first counted.
    private func look() {
        DispatchQueue.global(qos: .userInitiated).async {
            let (readable, missing) = Chromium.present()
            let sources = readable.map(ImportSource.chromium) + Mozilla.installed().map(ImportSource.mozilla)
            let lists = sources.map { ($0.id, $0.profiles, $0.usual) }
            DispatchQueue.main.async {
                for (id, list, last) in lists {
                    profileLists[id] = list
                    usual[id] = last
                }
                found = sources
                refused = missing
                if let first = source ?? sources.first { count(first) }
            }
        }
    }

    private func count(_ source: ImportSource) {
        let key = previewKey(source)
        guard previews[key] == nil else { return }
        let profile = profile(of: source)
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = source.preview(profile: profile)
            DispatchQueue.main.async { previews[key] = preview }
        }
    }

    /// The system's folder panel, opened at the browser's data; allowed, it
    /// joins the others and is picked.
    private func allow(_ browser: Chromium.Source) {
        Chromium.ask(for: browser) { trouble in
            allowTrouble = trouble
            guard trouble == nil else { return }
            source = .chromium(browser)
            brought = nil
            look()
        }
    }

    // MARK: - 4. sync

    private var syncing: some View {
        let cloud = SyncCloud.available
        return VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.3), .clear],
                                         center: .center, startRadius: 2, endRadius: 70))
                    .frame(width: 140, height: 140)
                Image(systemName: "icloud.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.white)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(6)
                            .background(Circle().fill(.white))
                            .offset(x: 10, y: 6)
                    }
            }
            .rise(0)
            VStack(spacing: 10) {
                Text("Your browser, on every Mac.")
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                Text("Spaces, pins, bookmarks and settings, through your own iCloud.")
                    .font(.system(size: 15.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .rise(1)
            Glass {
                VStack(alignment: .leading, spacing: 16) {
                    Point("lock.shield.fill", "End-to-end encrypted", "Only your devices hold the key. Not Apple, not us.")
                    Point("person.crop.circle.badge.checkmark", "No account to make", "Your Apple ID is all it takes.")
                    Point("bolt.fill", "In moments", "A pin added on one Mac is on the others before you switch.")
                }
            }
            .frame(maxWidth: 560)
            .rise(2)
            HStack(spacing: 12) {
                if sync.cloud {
                    Done("Syncing with iCloud")
                } else if sync.folder != nil {
                    Done("Syncing through a folder")
                } else {
                    if cloud {
                        Primary("Sync with iCloud", large: true) { sync.turnOnCloud() }
                    }
                    Ghost(cloud ? "Use a Folder Instead…" : "Sync Through a Folder…") { sync.choose() }
                }
            }
            .animation(Motion.settle, value: sync.way)
            .rise(3)
            if !cloud, !sync.on {
                Text("This copy of \(Store.name) isn't set up for iCloud yet, so a folder in iCloud Drive or Dropbox does the same job for now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .rise(4)
            }
        }
    }

    // MARK: - 5. fewer ads

    private var protection: some View {
        let popular = FilterLists.suggested.filter { $0.within == nil }.prefix(3)
        return VStack(alignment: .leading, spacing: 20) {
            Heading("Fewer ads, less tracking.", "Blocked before the page loads, so pages come in faster.")
                .rise(0)
            Glass {
                VStack(alignment: .leading, spacing: 14) {
                    Toggled("Block ads and trackers", "Built into the engine", on: $prefs.shielded)
                    if prefs.shielded {
                        Divider().overlay(Color.white.opacity(0.1))
                        Text("Add the lists other blockers use")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        ForEach(Array(popular)) { list in
                            Toggled(list.name, list.what, on: Binding(
                                get: { lists.sources.contains { $0.origin == list.origin } },
                                set: { on in
                                    if on { lists.add(list.origin) } else if let added = lists.sources.first(where: { $0.origin == list.origin }) {
                                        lists.remove(added.id)
                                    }
                                }))
                        }
                    }
                }
                .animation(Motion.settle, value: prefs.shielded)
            }
            .rise(1)
            Glass {
                HStack(spacing: 16) {
                    Badge(symbol: "link")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open links in \(Store.name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Links from Mail, Slack and other apps land here.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if isDefault {
                        Done("Default browser")
                    } else {
                        Primary(askedDefault ? "Asked…" : "Make Default") {
                            askedDefault = true
                            Links.becomeDefault { _ in isDefault = Links.isDefault }
                        }
                    }
                }
                .animation(Motion.settle, value: isDefault)
            }
            .rise(2)
            // Apple Intelligence, on a Mac that has it: on to start with.
            if OnDevice.available {
                Glass {
                    HStack(spacing: 16) {
                        Badge(symbol: "apple.intelligence")
                        Toggled("Apple Intelligence", "Shorter tab names and link summaries, worked out on this Mac",
                                on: Binding(get: { prefs.shortTitles || prefs.summarizesLinks },
                                            set: { on in prefs.shortTitles = on; prefs.summarizesLinks = on }))
                    }
                }
                .rise(3)
            }
            // Coding agents with full control (AgentFull): off to start with,
            // and only ever on by your own switch, here or in Settings.
            Glass {
                HStack(spacing: 16) {
                    Badge(symbol: "cursorarrow.rays")
                    Toggled("Let AI agents control \(Store.name)",
                            "Claude Code, Codex and others over MCP, once you allow each one",
                            on: Binding(get: { prefs.agents && prefs.agentsFull },
                                        set: { on in prefs.agents = on; prefs.agentsFull = on }))
                }
            }
            .rise(OnDevice.available ? 4 : 3)
        }
    }

    // MARK: - 6. all set

    private var done: some View {
        ZStack {
            Confetti(reduced: reduced)
                .allowsHitTesting(false)
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("You're all set.")
                        .font(.system(size: 50, weight: .semibold))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text("Six keys worth knowing. The rest are in Settings.")
                        .font(.system(size: 15.5))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .rise(0)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    Keycap("⌘T", "Go anywhere", delay: 1)
                    Keycap("⌘S", "Hide the sidebar", delay: 2)
                    Keycap("⌃Tab", "Recent tabs", delay: 3)
                    Keycap("⌘K", "Find a tab", delay: 4)
                    Keycap("⌥⌘N", "Split View", delay: 5)
                    Keycap("⇧⌘P", "Float a video", delay: 6)
                }
                .frame(maxWidth: 560)
                Primary("Start Browsing", large: true) { finish() }
                    .keyboardShortcut(.defaultAction)
                    .rise(7)
            }
        }
    }

    // MARK: - doing

    private func bringAll(from source: ImportSource) {
        // What was found empty isn't asked for: no keychain prompt for
        // passwords there aren't.
        let found = previews[previewKey(source)]
        let wantsPasswords = self.wantsPasswords && found?.passwords != 0
        let wantsBookmarks = self.wantsBookmarks && found?.bookmarks != 0
        let wantsHistory = self.wantsHistory && found?.places != 0
        let each = eachProfile(source)
        let profile = profile(of: source)
        if source.name == "Arc", wantsArcSpaces, FileManager.default.fileExists(atPath: Arc.file.path) {
            arcAfter = true
            arcProfile = profile
        }
        let extensions = wantsExtensions ? freshExtensions(previews[previewKey(source)]) : []
        bringing = true
        var lines: [String] = []
        let group = DispatchGroup()
        if wantsPasswords && source.importsPasswords {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result { try source.read(profile: profile) }
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let found):
                        let kept = browser.keep(found)
                        ImportRecords.note(source.name, passwords: kept)
                        lines.append("\(kept) passwords")
                    case .failure(Chromium.Trouble.noPassphrase):
                        lines.append("passwords need macOS's OK")
                    case .failure:
                        lines.append("no passwords readable")
                    }
                    group.leave()
                }
            }
        }
        if each, wantsBookmarks || wantsHistory {
            group.enter()
            browser.takeProfiles(from: source, bookmarks: wantsBookmarks, history: wantsHistory) { takes in
                let marks = takes.reduce(0) { $0 + $1.bookmarks }
                let places = takes.reduce(0) { $0 + $1.places }
                let made = takes.filter(\.made).count
                if wantsBookmarks { lines.append("\(marks) bookmarks") }
                if wantsHistory { lines.append("\(places) places") }
                if made > 0 { lines.append(made == 1 ? "1 new profile" : "\(made) new profiles") }
                group.leave()
            }
        } else {
            if wantsBookmarks {
                lines.append("\(browser.takeBookmarks(from: source, profile: profile).added) bookmarks")
            }
            if wantsHistory {
                group.enter()
                browser.takePlaces(from: source, profile: profile) { count in
                    lines.append("\(count) places")
                    group.leave()
                }
            }
        }
        // Arc's spaces and pins come once the onboarding is done (finish).
        if arcAfter, source.name == "Arc" { lines.append("spaces and pins right after this") }
        if #available(macOS 15.4, *), !extensions.isEmpty {
            // Asked about one at a time; the step can be left meanwhile.
            lines.append(extensions.count == 1 ? "1 extension to confirm" : "\(extensions.count) extensions to confirm")
            Task { @MainActor in
                let result = await ExtensionImport.install(extensions)
                browser.announce(result.said)
            }
        }
        group.notify(queue: .main) {
            bringing = false
            brought = lines.joined(separator: " · ")
            browser.relist()
        }
    }

    private func finish() {
        prefs.welcomed = true
        withAnimation(Motion.settle) { browser.welcoming = false }
        if arcAfter {
            let profile = arcProfile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Self.bringArc(into: browser, profile: profile)
            }
        }
    }

    /// Arc's spaces and pins, as Bring Things Over brings them, said once
    /// they're in. Unreadable, the page is where it can be tried again.
    static func bringArc(into browser: Browser, profile: String?) {
        guard let sidebar = Arc.sidebar(profile: profile) else {
            browser.lead(to: InternalPage(.importing, "Arc"))
            return
        }
        // Its icons are read from Arc's own files, as the page does.
        let source = Chromium.known.first { $0.name == "Arc" }.map(ImportSource.chromium)
        let (spaces, pins, tabs) = browser.takeArc(sidebar, from: source, profile: profile)
        ImportRecords.note("Arc", spaces: spaces, pinned: pins + tabs)
        func count(_ n: Int, _ one: String) -> String { n == 1 ? "1 \(one)" : "\(n.formatted()) \(one)s" }
        browser.announce(spaces + pins + tabs == 0 ? "Arc's spaces and pins were all here already"
                         : "From Arc: \(count(spaces, "space")), \(count(pins + tabs, "pin"))")
    }
}

// MARK: - the stage

/// The ground behind it all: the window's own, black as a space with no
/// colour is, and the first space's colour, gradient and grain over it,
/// drawn a step stronger than the window wears them, so what is picked on
/// Make It Yours fills the stage as it is picked. A soft light drifts over
/// it, the edges in shade.
private struct Stage: View {
    @ObservedObject var browser: Browser
    let reduced: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { time in
            let t = reduced ? 0 : time.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(white: 0.075)
                SpaceWash(look: browser.wash, space: browser.washSpace)
                    .environment(\.washStrength, browser.washStrength == .subtle ? .rich : browser.washStrength)
                    .environment(\.washGrain, browser.washGrain)
                    .animation(.easeInOut(duration: 0.6), value: browser.wash)
                // A soft light drifting slowly over it, as through frosted glass.
                RadialGradient(colors: [.white.opacity(0.07), .clear],
                               center: UnitPoint(x: 0.5 + 0.25 * Foundation.sin(t * 0.07), y: 0.32 + 0.12 * Foundation.cos(t * 0.09)),
                               startRadius: 0, endRadius: 640)
                GrainWash(opacity: 0.04)
                RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 300, endRadius: 1000)
                // A soft shade at the foot, for the buttons to stand on.
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
            }
        }
    }
}

// MARK: - pieces

private extension View {
    /// In from a little below, blurred to sharp, the `order`th on its step.
    func rise(_ order: Int) -> some View { modifier(Rise(order: order)) }
}

private struct Rise: ViewModifier {
    let order: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduced ? 0 : 14)
            .blur(radius: shown || Motion.reduced ? 0 : 6)
            .onAppear {
                withAnimation(Motion.reduced ? .easeOut(duration: 0.2)
                              : .spring(response: 0.6, dampingFraction: 0.85).delay(0.08 + Double(order) * 0.07)) {
                    shown = true
                }
            }
    }
}

/// The welcome's title, opening out: from widely spaced and soft to set
/// tight and sharp, as the stage comes up.
private struct Unfurl: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .tracking(shown || Motion.reduced ? -1 : 14)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || Motion.reduced ? 0 : 10)
            .scaleEffect(shown || Motion.reduced ? 1 : 0.96)
            .onAppear {
                withAnimation(Motion.reduced ? .easeOut(duration: 0.2) : .spring(response: 1.2, dampingFraction: 0.9).delay(0.15)) {
                    shown = true
                }
            }
    }
}

/// Drifting up and down a few points, forever.
private struct Floating<Content: View>: View {
    let reduced: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { time in
            let t = time.date.timeIntervalSinceReferenceDate
            content()
                .offset(y: reduced ? 0 : 5 * Foundation.sin(t * 1.3))
                .rotationEffect(.degrees(reduced ? 0 : 1.5 * Foundation.sin(t * 0.9)))
        }
    }
}

private struct Heading: View {
    let title: String
    let line: String
    init(_ title: String, _ line: String) { self.title = title; self.line = line }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white)
            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.58))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A frosted card.
private struct Glass<Content: View>: View {
    var highlight = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Dark glass, the same on any desktop: a deep, slightly
            // clear ground, a breath of white, and an edge lit from above.
            .background(Color.white.opacity(highlight ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(highlight ? 0.24 : 0.14), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
    }
}

private struct Row<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control
    init(_ title: String, @ViewBuilder control: @escaping () -> Control) { self.title = title; self.control = control }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 92, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }
}

/// Choices as glass chips; the chosen one lit, the light sliding between.
private struct Chips<Option: Hashable>: View {
    let options: [(Option, String, String?)]
    @Binding var selection: Option
    @Namespace private var lit

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option, title, symbol in
                let on = option == selection
                Button { withAnimation(Motion.settle) { selection = option } } label: {
                    HStack(spacing: 5) {
                        if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                        Text(title).font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(on ? Color.black : .white.opacity(0.75))
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        if on {
                            Capsule().fill(.white).matchedGeometryEffect(id: "lit", in: lit)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// The wheel's own swatch, after the five: every hue round a ring. It opens
/// the space's whole picker — the wheel, gradients, grain — in a popover;
/// whatever is picked there turns spaces on to wear it, as a swatch does.
private struct WheelButton: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @State private var open = false
    @State private var hovering = false
    /// The hues turning: from the pointer coming in until the glow has faded.
    @State private var spinning = false

    private var custom: Bool {
        let space = browser.space
        return space.gradient != nil || (space.look != nil && space.colour == 0) || space.grain != nil
    }

    private static let hues = AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                              center: .center)

    var body: some View {
        Button { open = true } label: {
            // Under the pointer the hues turn, slowly, and glow behind it;
            // the + stays upright, so it never reads as a ×. Only the turn is
            // drawn frame by frame (Turning): the glow's fade is outside it,
            // where each new frame doesn't set it straight to where it ends.
            ZStack {
                Turning(on: spinning) { Circle().fill(WheelButton.hues) }
                    .blur(radius: 7)
                    .scaleEffect(hovering ? 1.15 : 0.9)
                    .opacity(hovering ? 0.75 : 0)
                Turning(on: spinning) { Circle().fill(WheelButton.hues) }
                Circle().fill(RadialGradient(colors: [.white.opacity(hovering ? 0.95 : 0.85), .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: hovering ? 10 : 9))
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.black.opacity(hovering ? 0.7 : 0.55))
                    .opacity(custom ? 0 : 1)
            }
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().strokeBorder(.white, lineWidth: custom ? 2 : 0))
            .scaleEffect(hovering ? 1.16 : custom ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        // In and out on a smooth curve with no bounce: a spring that
        // overshot faded the glow past nothing and back, a flash on the way
        // out. The hues keep turning until the glow has gone.
        .onHover { on in
            if on { spinning = true }
            withAnimation(on ? .smooth(duration: 0.45) : .smooth(duration: 0.55)) { hovering = on }
            if !on {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if !hovering { spinning = false } }
            }
        }
        .help("More colours, gradients and grain")
        .accessibilityLabel("More colours")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            SpaceLookPicker(browser: browser, id: browser.spaceID)
                // Dark like the stage it opens over, whatever the window's
                // look is set to: light, its frame went pale under text
                // drawn for the dark.
                .preferredColorScheme(.dark)
                // A drag the popover closed under keeps nothing but what was.
                .onDisappear { if LookDraft.shared.preview != nil { LookDraft.shared.end() } }
        }
        .onChange(of: browser.space.look) { _, look in
            if look != nil, !prefs.usesSpaces { prefs.usesSpaces = true }
        }
    }
}

/// Its content turning slowly while `on`, and resting where it got to
/// when not. Only the turn is drawn every frame.
private struct Turning<Content: View>: View {
    let on: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !on || Motion.reduced)) { time in
            content()
                .rotationEffect(.degrees(Motion.reduced ? 0 : (time.date.timeIntervalSinceReferenceDate * 80).truncatingRemainder(dividingBy: 360)))
        }
    }
}

/// The first space's colour: none, then the five.
private struct Swatches: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Spaces.colours.indices, id: \.self) { i in
                Button { withAnimation(Motion.settle) { selection = i } } label: {
                    ZStack {
                        if i == 0 {
                            Circle().strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        } else {
                            Circle().fill(Spaces.colours[i])
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .overlay(Circle().strokeBorder(.white, lineWidth: selection == i ? 2 : 0))
                    .scaleEffect(selection == i ? 1.08 : 1)
                    .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .help(Spaces.colourNames[i])
            }
        }
    }
}

/// A small drawing of the window, as it will look with what is picked.
private struct MiniWindow: View {
    let layout: TabsLayout
    let roomy: Bool
    let look: Look
    let tint: Color?

    private var dark: Bool { look == .dark || (look == .system && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) }
    private var ground: Color { dark ? Color(white: 0.11) : Color(white: 0.96) }
    private var page: Color { dark ? Color(white: 0.16) : .white }
    private var ink: Color { dark ? .white : .black }

    var body: some View {
        GeometryReader { box in
            let w = box.size.width, h = box.size.height
            let side = w * 0.27, row: CGFloat = roomy ? h * 0.075 : h * 0.058
            let strip = row * 1.6 + 10
            let pageRect: CGRect = {
                switch layout {
                case .top: return CGRect(x: 8, y: strip, width: w - 16, height: h - strip - 8)
                case .right: return CGRect(x: 8, y: 8, width: w - side - 12, height: h - 16)
                default: return CGRect(x: side + 4, y: 8, width: w - side - 12, height: h - 16)
                }
            }()
            ZStack(alignment: .topLeading) {
                ground
                if let tint { tint.opacity(dark ? 0.16 : 0.1) }
                // The page, a card beside or under the tabs.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(page)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .frame(width: pageRect.width, height: pageRect.height)
                    .offset(x: pageRect.minX, y: pageRect.minY)
                // Lines of a page.
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.75)).frame(width: pageRect.width * 0.45, height: 9)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.12)).frame(width: pageRect.width * (i == 4 ? 0.5 : 0.8), height: 5)
                    }
                }
                .offset(x: pageRect.minX + 18, y: pageRect.minY + 22)
                // The tabs.
                if layout == .top {
                    HStack(spacing: 4) {
                        lights.padding(.trailing, 8)
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 5).fill(ink.opacity(i == 0 ? 0.14 : 0.06))
                                .frame(width: (w - 90) / 4.6, height: row)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: strip)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        if layout != .right { lights.padding(.bottom, 6) } else { Spacer().frame(height: 14) }
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.08)).frame(height: roomy ? row * 1.15 : row)
                            }
                        }
                        .padding(.bottom, 4)
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 6) {
                                Circle().fill(ink.opacity(0.3)).frame(width: row * 0.42, height: row * 0.42)
                                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.3)).frame(height: roomy ? 5 : 4)
                            }
                            .padding(.horizontal, 7)
                            .frame(height: row)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(i == 0 ? 0.12 : 0)))
                        }
                    }
                    .padding(10)
                    .frame(width: side, alignment: .topLeading)
                    .offset(x: layout == .right ? w - side : 0)
                }
                if layout == .right { lights.offset(x: 14, y: 14) }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 40, y: 24)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: layout)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: roomy)
            .animation(.easeInOut(duration: 0.35), value: look)
        }
    }

    private var lights: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(ink.opacity(0.22)).frame(width: 8, height: 8)
            }
        }
    }
}

private struct Primary: View {
    let title: String
    var large = false
    let act: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, large: Bool = false, act: @escaping () -> Void) {
        self.title = title
        self.large = large
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: large ? 15 : 13.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, large ? 26 : 18)
                .frame(height: large ? 46 : 36)
                .background(Capsule().fill(.white))
                .shadow(color: .white.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 18 : 10)
                .scaleEffect(hovering && enabled ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .animation(Motion.settle, value: hovering)
    }
}

private struct Ghost: View {
    let title: String
    let act: () -> Void
    @State private var hovering = false
    init(_ title: String, act: @escaping () -> Void) { self.title = title; self.act = act }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.75))
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A button that gives a little under the press.
private struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.97 : 1)
            // Instant on the press, back without a bounce (PressStyle).
            .animation(Motion.out(configuration.isPressed ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

/// What was done, said with a tick that pops in.
private struct Done: View {
    let text: String
    @State private var shown = false
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .scaleEffect(shown ? 1 : 0.3)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { shown = true } }
    }
}

private struct Toggled: View {
    let title: String
    let detail: String
    @Binding var on: Bool
    /// Nothing there to bring: shown off and quiet, not to be switched.
    var empty = false
    init(_ title: String, _ detail: String, on: Binding<Bool>, empty: Bool = false) {
        self.title = title; self.detail = detail; _on = on; self.empty = empty
    }

    var body: some View {
        let on = self.on && !empty
        Button { withAnimation(Motion.settle) { self.on.toggle() } } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                }
                Spacer(minLength: 8)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Color.white : Color.white.opacity(0.16))
                        .frame(width: 40, height: 24)
                    Circle().fill(on ? Color.black : .white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
            .opacity(empty ? 0.45 : 1)
        }
        // A row with a switch isn't a button to the eye: a click anywhere on
        // it flips the switch, and only the switch moves.
        .buttonStyle(StillPress())
        .disabled(empty)
        .animation(Motion.settle, value: empty)
        .animation(Motion.settle, value: detail)
    }
}

/// A press that changes nothing about what's pressed: for a row whose own
/// switch shows the answer.
private struct StillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// One of the reasons on the sync step.
private struct Point: View {
    let symbol: String
    let title: String
    let line: String
    init(_ symbol: String, _ title: String, _ line: String) { self.symbol = symbol; self.title = title; self.line = line }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(line).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Badge: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom)))
    }
}

/// A key worth knowing, coming in on its turn.
private struct Keycap: View {
    let keys: String
    let what: String
    let delay: Int
    init(_ keys: String, _ what: String, delay: Int) { self.keys = keys; self.what = what; self.delay = delay }

    var body: some View {
        VStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minWidth: 58, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
            Text(what)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .rise(delay)
    }
}

/// A short burst of white and grey as the last step comes in.
private struct Confetti: View {
    let reduced: Bool
    @State private var start = Date()

    private struct Bit {
        let angle: Double, speed: Double, spin: Double, size: CGFloat, color: Color, delay: Double
    }

    private static let bits: [Bit] = {
        var generator = SystemRandomNumberGenerator()
        // White and greys, as the rest of it: sparkle, not a party.
        let colors: [Color] = [.white, .white, Color(white: 0.8), Color(white: 0.6), Color(white: 0.42)]
        return (0..<70).map { _ in
            Bit(angle: Double.random(in: -Double.pi...0, using: &generator),
                speed: Double.random(in: 260...620, using: &generator),
                spin: Double.random(in: -6...6, using: &generator),
                size: CGFloat.random(in: 4...8, using: &generator),
                color: colors.randomElement(using: &generator) ?? .white,
                delay: Double.random(in: 0...0.25, using: &generator))
        }
    }()

    var body: some View {
        if reduced {
            EmptyView()
        } else {
            TimelineView(.animation) { time in
                let elapsed = time.date.timeIntervalSince(start)
                Canvas { context, size in
                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                    for bit in Confetti.bits {
                        let t = elapsed - bit.delay
                        guard t > 0, t < 2.6 else { continue }
                        let x = origin.x + cos(bit.angle) * bit.speed * t
                        let y = origin.y + sin(bit.angle) * bit.speed * t + 420 * t * t
                        var piece = context
                        piece.opacity = max(0, 1 - t / 2.6)
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(bit.spin * t))
                        piece.fill(Path(roundedRect: CGRect(x: -bit.size / 2, y: -bit.size / 4, width: bit.size, height: bit.size / 2), cornerRadius: 1),
                                   with: .color(bit.color))
                    }
                }
            }
            .onAppear { start = Date() }
        }
    }
}
