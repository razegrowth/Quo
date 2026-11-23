import XCTest
@testable import Search

/// Strong passwords and cards (Cards.swift): the passwords' shape and
/// randomness, a card number checked before it's kept, its kind, and what
/// goes into a checkout's boxes.
final class CardsTests: XCTestCase {
    func testAStrongPasswordHasSafarisShape() {
        for _ in 0..<200 {
            let made = StrongPassword.make()
            XCTAssertNotNil(made.range(of: #"^[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}$"#, options: .regularExpression), made)
            XCTAssertNotNil(made.rangeOfCharacter(from: .uppercaseLetters), made)
            XCTAssertNotNil(made.rangeOfCharacter(from: .decimalDigits), made)
            XCTAssertNil(made.rangeOfCharacter(from: CharacterSet(charactersIn: "lIoO01")), "nothing that reads two ways: \(made)")
        }
        XCTAssertEqual(Set((0..<50).map { _ in StrongPassword.make() }).count, 50, "never the same twice")
    }

    func testABoxThatTakesFewerGetsAShorterOne() {
        XCTAssertEqual(StrongPassword.make(fitting: 12).count, 12)
        XCTAssertEqual(StrongPassword.make(fitting: 4).count, 8, "never shorter than eight")
        XCTAssertEqual(StrongPassword.make(fitting: 64).count, 20)
    }

    func testANumberIsCheckedBeforeItsKept() {
        XCTAssertTrue(Cards.valid("4242 4242 4242 4242"))
        XCTAssertTrue(Cards.valid("5555-5555-5555-4444"))
        XCTAssertTrue(Cards.valid("378282246310005"))
        XCTAssertFalse(Cards.valid("4242 4242 4242 4241"), "one digit off")
        XCTAssertFalse(Cards.valid("4242"), "too short")
        XCTAssertFalse(Cards.valid("4242 4242 4242 424a"), "a letter")
    }

    func testItsKindByItsFirstDigits() {
        XCTAssertEqual(Cards.kind(of: "4242424242424242"), "Visa")
        XCTAssertEqual(Cards.kind(of: "5555555555554444"), "Mastercard")
        XCTAssertEqual(Cards.kind(of: "2223003122003222"), "Mastercard")
        XCTAssertEqual(Cards.kind(of: "378282246310005"), "American Express")
        XCTAssertEqual(Cards.kind(of: "6011111111111117"), "Discover")
        XCTAssertEqual(Cards.kind(of: "3530111333300000"), "JCB")
    }

    func testWhatGoesIntoTheBoxes() {
        let card = KeptCard(name: "Ada King Lovelace", kind: "Visa", last4: "4242", month: 4, year: 2030)
        let fields = Cards.fields(card, number: "4242424242424242")
        XCTAssertEqual(fields["cc-number"], "4242424242424242")
        XCTAssertEqual(fields["cc-exp"], "04/30")
        XCTAssertEqual(fields["cc-exp-month"], "04")
        XCTAssertEqual(fields["cc-exp-year"], "2030")
        XCTAssertEqual(fields["cc-given-name"], "Ada")
        XCTAssertEqual(fields["cc-family-name"], "King Lovelace")
        XCTAssertNil(fields["cc-csc"], "the security code is never kept or filled")
        XCTAssertEqual(card.title, "Visa •••• 4242")
    }
}
