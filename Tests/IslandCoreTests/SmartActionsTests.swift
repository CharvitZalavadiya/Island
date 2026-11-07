import Testing
import Foundation
@testable import IslandCore

@Test func aWebLinkOffersOpen() {
    #expect(SmartAction.detect(in: "https://example.com") == [.openLink(URL(string: "https://example.com")!)])
    #expect(SmartAction.detect(in: "  http://localhost:3000/path?x=1\n")
        == [.openLink(URL(string: "http://localhost:3000/path?x=1")!)])
}

@Test func textThatMerelyContainsALinkHasNoActions() {
    #expect(SmartAction.detect(in: "see https://example.com for details").isEmpty)
}

@Test func nonWebSchemesAndBrokenLinksAreIgnored() {
    #expect(SmartAction.detect(in: "javascript:alert(1)").isEmpty)
    #expect(SmartAction.detect(in: "https://").isEmpty)
    #expect(SmartAction.detect(in: "ftp://example.com/file").isEmpty)
}

@Test func aHexColorOffersCopyAsRGB() {
    #expect(SmartAction.detect(in: "#FF8800") == [.copyRGB("255, 136, 0")])
    #expect(SmartAction.detect(in: "#ff8800") == [.copyRGB("255, 136, 0")])
    #expect(SmartAction.detect(in: "#f80") == [.copyRGB("255, 136, 0")])
    #expect(SmartAction.detect(in: "#000000") == [.copyRGB("0, 0, 0")])
}

@Test func hexWithoutAHashOrWithBadDigitsIsNotAColor() {
    #expect(SmartAction.detect(in: "ff8800").isEmpty)
    #expect(SmartAction.detect(in: "#GGGGGG").isEmpty)
    #expect(SmartAction.detect(in: "#12345").isEmpty)
    #expect(SmartAction.detect(in: "#1234567").isEmpty)
}

@Test func anEmailAddressOffersCompose() {
    #expect(SmartAction.detect(in: "a@b.co") == [.composeMail("a@b.co")])
    #expect(SmartAction.detect(in: " first.last+tag@sub.example.com ") == [.composeMail("first.last+tag@sub.example.com")])
}

@Test func notQuiteEmailsAreIgnored() {
    #expect(SmartAction.detect(in: "a@b").isEmpty)
    #expect(SmartAction.detect(in: "@example.com").isEmpty)
    #expect(SmartAction.detect(in: "write to a@b.co please").isEmpty)
}

@Test func plainTextHasNoActions() {
    #expect(SmartAction.detect(in: "hello world").isEmpty)
    #expect(SmartAction.detect(in: "").isEmpty)
}
