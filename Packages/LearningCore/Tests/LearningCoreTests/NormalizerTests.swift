import XCTest
@testable import LearningCore

final class NormalizerTests: XCTestCase {
    func testBasicNormalization() {
        XCTAssertEqual(TextNormalizer.normalize("  Hello,   World!! "), "hello world")
        XCTAssertEqual(TextNormalizer.normalize("“Hello”; (my) friend…"), "hello my friend")
        XCTAssertEqual(TextNormalizer.normalize("I don’t know."), "i don't know")
        XCTAssertEqual(TextNormalizer.normalize("Où est l’Été ? Là !"), "où est l'été là")
        XCTAssertEqual(TextNormalizer.normalize("Tom\u{00A0}and Anna: friends."), "tom and anna friends")
        XCTAssertEqual(TextNormalizer.normalize(""), "")
    }

    func testContractionsAreExpandedToVariants() {
        func canon(_ s: String) -> [String] { TextNormalizer.canonicalStrings(s) }
        XCTAssertEqual(canon("I'm happy"), ["i am happy"])
        XCTAssertEqual(canon("doesn't"), ["does not"])
        XCTAssertEqual(canon("He doesn't go"), ["he does not go"])
        XCTAssertEqual(canon("can't"), canon("cannot"))
        XCTAssertEqual(canon("can't"), canon("can not"))
        XCTAssertEqual(canon("won't"), ["will not"])
        XCTAssertEqual(canon("She'll come"), ["she will come"])
        XCTAssertEqual(canon("you're"), ["you are"])
        XCTAssertEqual(canon("They've left"), ["they have left"])
        XCTAssertEqual(canon("Let's go"), ["let us go"])
        XCTAssertEqual(Set(canon("He's here")), ["he is here", "he has here"])
        XCTAssertEqual(Set(canon("I'd go")), ["i would go", "i had go"])
        // Genitive 's is kept (and may also be read as "is").
        XCTAssertTrue(canon("Tom's book").contains("tom's book"))
        XCTAssertTrue(canon("Tom's a teacher").contains("tom is a teacher"))
        // The same answer with or without contraction has a common canonical form.
        XCTAssertFalse(Set(canon("She isn't tired")).isDisjoint(with: Set(canon("She is not tired"))))
        XCTAssertFalse(Set(canon("It's late")).isDisjoint(with: Set(canon("It is late"))))
    }

    func testNumbersSpellingAndHyphens() {
        XCTAssertEqual(TextNormalizer.canonicalForm("I have 5 apples"), "i have five apples")
        XCTAssertEqual(TextNormalizer.canonicalForm("I am 20"), "i am twenty")
        XCTAssertEqual(TextNormalizer.canonicalForm("0"), "zero")
        XCTAssertEqual(TextNormalizer.canonicalForm("I have 21 books"), "i have 21 books")
        XCTAssertEqual(TextNormalizer.canonicalForm("My favourite colour is grey"), TextNormalizer.canonicalForm("my favorite color is gray"))
        XCTAssertEqual(TextNormalizer.canonicalForm("Mum travelled"), TextNormalizer.canonicalForm("Mom traveled"))
        XCTAssertFalse(Set(TextNormalizer.canonicalStrings("e-mail")).isDisjoint(with: Set(TextNormalizer.canonicalStrings("email"))))
    }

    func testFrenchKeepsStepsOneToThreeOnly() {
        XCTAssertEqual(TextNormalizer.canonicalForm("J'ai 5 ans", english: false), "j'ai 5 ans")
        XCTAssertEqual(TextNormalizer.foldAccents("Été à côté"), "Ete a cote")
    }

    func testDamerauLevenshtein() {
        XCTAssertEqual(damerauLevenshtein("recieve", "receive"), 1)
        XCTAssertEqual(damerauLevenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(damerauLevenshtein("", "abc"), 3)
        XCTAssertEqual(damerauLevenshtein("same", "same"), 0)
    }

    func testSplitMixIsDeterministic() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
        var c = SplitMix64(seed: 43), d = SplitMix64(seed: 42)
        XCTAssertNotEqual(d.next(), c.next())
        XCTAssertEqual(a.nextUUID(), b.nextUUID())
    }
}
