import AppKit
import LocalAuthentication
import SwiftUI

// Your cards, filled in at checkout as Safari fills them: under a box for a
// card's number, name or expiry, the cards you keep here, and a pick puts
// them into the form once you've said so with Touch ID (or your password).
//
// What's kept, and where:
//   - the number in the Mac's keychain, Quo's own item, read only for the
//     card picked, only after Touch ID;
//   - beside it, in Quo's folder, what the list shows without asking: the
//     name on the card, its kind (Visa, Mastercard…), the last four digits
//     and the expiry. Never the number, never the security code.
// The security code is never kept: after a pick the caret goes to its box,
// for you to type it, as Safari does.
//
// A card's boxes inside a payment provider's own frame (Stripe's, for one)
// are that provider's page, not the site's, and aren't filled.

struct KeptCard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: String
    var last4: String
    var month: Int
    var year: Int

    /// "Visa •••• 4242".
    var title: String { "\(kind) •••• \(last4)" }
    var expiry: String { String(format: "%02d/%02d", month, year % 100) }
    var detail: String { [name, "Expires \(expiry)"].filter { !$0.isEmpty }.joined(separator: " · ") }
    var expired: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return year < now.year! || (year == now.year! && month < now.month!)
    }
}

@MainActor
final class Cards: ObservableObject {
    static let shared = Cards()
    @Published private(set) var kept: [KeptCard] = []

    private static let service = "\(Store.home).cards"
    private var file: URL { Store.folder.appendingPathComponent("cards.json") }
    /// A test run's numbers, gone when it quits.
    private var rehearsal: [UUID: String] = [:]
    /// A test run's Touch ID: yes unless a probe says no.
    static var testAllows = true

    init() {
        if let data = try? Data(contentsOf: file), let cards = try? JSONDecoder().decode([KeptCard].self, from: data) {
            kept = cards
        }
    }

    // MARK: numbers

    /// Only digits, 12 to 19 of them, and the Luhn check right: a number
    /// mistyped by a digit is caught before it's kept.
    nonisolated static func valid(_ number: String) -> Bool {
        let digits = number.filter(\.isNumber)
        guard (12...19).contains(digits.count), digits.count == number.filter({ !$0.isWhitespace && $0 != "-" }).count else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            var d = Int(String(ch))!
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    /// The kind of card a number is, by its first digits.
    nonisolated static func kind(of number: String) -> String {
        let d = number.filter(\.isNumber)
        func starts(_ range: ClosedRange<Int>, _ count: Int) -> Bool {
            guard d.count >= count, let head = Int(d.prefix(count)) else { return false }
            return range.contains(head)
        }
        if d.hasPrefix("4") { return "Visa" }
        if starts(51...55, 2) || starts(2221...2720, 4) { return "Mastercard" }
        if d.hasPrefix("34") || d.hasPrefix("37") { return "American Express" }
        if d.hasPrefix("6011") || d.hasPrefix("65") || starts(644...649, 3) { return "Discover" }
        if starts(3528...3589, 4) { return "JCB" }
        if d.hasPrefix("62") { return "UnionPay" }
        if d.hasPrefix("36") || d.hasPrefix("38") || starts(300...305, 3) { return "Diners Club" }
        return "Card"
    }

    // MARK: keeping

    enum Added: Equatable { case kept, invalid, failed }

    func add(name: String, number: String, month: Int, year: Int) -> Added {
        let digits = number.filter(\.isNumber)
        let year = year < 100 ? 2000 + year : year
        guard Self.valid(number), (1...12).contains(month), (2000...2100).contains(year) else { return .invalid }
        let card = KeptCard(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: Self.kind(of: digits),
                            last4: String(digits.suffix(4)), month: month, year: year)
        guard store(digits, for: card.id) else { return .failed }
        kept.append(card)
        save()
        return .kept
    }

    func remove(_ card: KeptCard) {
        if Store.testing {
            rehearsal[card.id] = nil
        } else {
            SecItemDelete(query(card.id) as CFDictionary)
        }
        kept.removeAll { $0.id == card.id }
        save()
    }

    /// Every card, gone: Clear History's "cards" too, or a probe's tidy-up.
    func removeAll() { kept.forEach(remove) }

    private func save() {
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: file, options: [.atomic])
    }

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: id.uuidString]
    }

    private func store(_ number: String, for id: UUID) -> Bool {
        if Store.testing {
            rehearsal[id] = number
            return true
        }
        var item = query(id)
        item[kSecValueData as String] = Data(number.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "\(Store.name) card"
        SecItemDelete(query(id) as CFDictionary)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// The card's number, after Touch ID (or the Mac's password), or nil if
    /// you said no or it can't be read.
    func number(of card: KeptCard, reason: String) async -> String? {
        guard await Self.allowed(reason) else { return nil }
        if Store.testing { return rehearsal[card.id] }
        var asked = query(card.id)
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Touch ID, or the Mac's password where there is none.
    static func allowed(_ reason: String) async -> Bool {
        if Store.testing { return testAllows }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// What goes into a checkout's boxes for a card, by the autocomplete
    /// name of each: the number, the name in parts, the expiry three ways.
    nonisolated static func fields(_ card: KeptCard, number: String) -> [String: String] {
        let parts = card.name.split(separator: " ")
        return [
            "cc-number": number,
            "cc-name": card.name,
            "cc-given-name": parts.first.map(String.init) ?? "",
            "cc-family-name": parts.count > 1 ? parts.dropFirst().joined(separator: " ") : "",
            "cc-exp": card.expiry,
            "cc-exp-month": String(format: "%02d", card.month),
            "cc-exp-year": String(card.year),
            "cc-type": card.kind,
        ]
    }

    // MARK: asking

    /// Settings' Add Card…: the name, number and expiry, asked in one sheet.
    static func ask(in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Add a Card"
        alert.informativeText = "The number is kept in your Mac's keychain and filled only after Touch ID. The security code is never kept."
        let name = NSTextField(frame: NSRect(x: 0, y: 64, width: 280, height: 24))
        name.placeholderString = "Name on card"
        let number = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        number.placeholderString = "Card number"
        let expiry = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        expiry.placeholderString = "MM/YY"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 88))
        [name, number, expiry].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: "Add Card")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        let answer = { (response: NSApplication.ModalResponse) in
            guard response == .alertFirstButtonReturn else { return }
            let bits = expiry.stringValue.split { !$0.isNumber }.compactMap { Int($0) }
            let month = bits.first ?? 0, year = bits.count > 1 ? bits[1] : 0
            let added = MainActor.assumeIsolated { shared.add(name: name.stringValue, number: number.stringValue, month: month, year: year) }
            if added != .kept {
                let oops = NSAlert()
                oops.messageText = added == .invalid ? "That card doesn't look right" : "The card couldn't be kept"
                oops.informativeText = added == .invalid ? "Check the number and the expiry (MM/YY)." : "The keychain didn't take it."
                oops.runModal()
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: answer) } else { answer(alert.runModal()) }
    }
}

/// Settings › Passwords › Cards: each card kept, and Add Card….
struct CardsList: View {
    @ObservedObject var cards: Cards
    @State private var hovering: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(cards.kept) { card in
                HStack(spacing: 10) {
                    Image(systemName: "creditcard")
                        .foregroundStyle(Palette.muted)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                        Text(card.detail + (card.expired ? " · Expired" : ""))
                            .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Pill("Remove") { cards.remove(card) }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Pill(cards.kept.isEmpty ? "Add Card…" : "Add Another Card…") { Cards.ask(in: NSApp.keyWindow) }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A strong password for a new account, as Safari makes them: three runs of
/// six letters and digits joined by hyphens ("hqdvbm-7Kfa2r-tozpew"), one
/// capital and one digit at least, nothing that reads two ways (l, 1, o, 0).
/// Fewer characters, without hyphens, where the box takes fewer.
enum StrongPassword {
    private static let lower = Array("abcdefghijkmnpqrstuvwxyz")
    private static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")

    static func make(fitting most: Int? = nil) -> String {
        var rng = SystemRandomNumberGenerator()
        let pool = lower + lower + digits
        let short = (most ?? 0) > 0 && most! < 20
        let length = short ? max(8, most!) : 18
        var chars = (0..<length).map { _ in pool.randomElement(using: &rng)! }
        // One capital and one digit, in different places.
        let at = Array(0..<length).shuffled(using: &rng)
        chars[at[0]] = upper.randomElement(using: &rng)!
        chars[at[1]] = digits.randomElement(using: &rng)!
        let text = String(chars)
        guard !short else { return text }
        return [text.prefix(6), text.dropFirst(6).prefix(6), text.suffix(6)].map(String.init).joined(separator: "-")
    }
}
