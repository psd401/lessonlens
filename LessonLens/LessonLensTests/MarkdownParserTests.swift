import XCTest
@testable import LessonLens

final class MarkdownParserTests: XCTestCase {
    func testBlankLinesSeparateParagraphs() {
        let blocks = MarkdownParser.blocks(from: "First paragraph.\nSame paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(blocks, [
            .paragraph("First paragraph.\nSame paragraph."),
            .paragraph("Second paragraph.")
        ])
    }

    func testBulletMarkers() {
        let blocks = MarkdownParser.blocks(from: "* One\n- Two\n+ Three")
        XCTAssertEqual(blocks, [
            .bullet("One", indent: 0),
            .bullet("Two", indent: 0),
            .bullet("Three", indent: 0)
        ])
    }

    func testNestedBulletIndent() {
        let blocks = MarkdownParser.blocks(from: "* Outer\n    * Inner")
        XCTAssertEqual(blocks, [
            .bullet("Outer", indent: 0),
            .bullet("Inner", indent: 2)
        ])
    }

    func testNumberedMarkers() {
        let blocks = MarkdownParser.blocks(from: "1. Pose the question\n2) Wait five seconds")
        XCTAssertEqual(blocks, [
            .numbered("Pose the question", number: 1, indent: 0),
            .numbered("Wait five seconds", number: 2, indent: 0)
        ])
    }

    func testIndentedLineContinuesListItem() {
        let blocks = MarkdownParser.blocks(from: "* Cold call after the pause\n  so every student prepares")
        XCTAssertEqual(blocks, [.bullet("Cold call after the pause so every student prepares", indent: 0)])
    }

    func testHeadingsBecomeHeadingBlocks() {
        let blocks = MarkdownParser.blocks(from: "## Next steps\nTry this tomorrow.")
        XCTAssertEqual(blocks, [.heading("Next steps"), .paragraph("Try this tomorrow.")])
    }

    func testBoldAtLineStartIsNotABullet() {
        let blocks = MarkdownParser.blocks(from: "**Wait time** was effective.")
        XCTAssertEqual(blocks, [.paragraph("**Wait time** was effective.")])
    }

    func testDecimalIsNotANumberedItem() {
        let blocks = MarkdownParser.blocks(from: "3.5 seconds of wait time")
        XCTAssertEqual(blocks, [.paragraph("3.5 seconds of wait time")])
    }

    func testHorizontalRulesAreDropped() {
        let blocks = MarkdownParser.blocks(from: "Before\n---\nAfter")
        XCTAssertEqual(blocks, [.paragraph("Before"), .paragraph("After")])
    }

    func testEmptyTextHasNoBlocks() {
        XCTAssertEqual(MarkdownParser.blocks(from: ""), [])
    }

    func testInlineBoldAndItalicsStripMarkers() {
        let text = MarkdownParser.inline("You used **wait time** and *cold calls*.")
        XCTAssertEqual(String(text.characters), "You used wait time and cold calls.")
    }

    func testInlineBoldHasStrongEmphasis() {
        let text = MarkdownParser.inline("**wait time**")
        let intents = text.runs.compactMap(\.inlinePresentationIntent)
        XCTAssertTrue(intents.contains { $0.contains(.stronglyEmphasized) })
    }

    func testUnclosedBoldKeepsLiteralText() {
        let text = MarkdownParser.inline("**unclosed bold")
        XCTAssertEqual(String(text.characters), "**unclosed bold")
    }
}
