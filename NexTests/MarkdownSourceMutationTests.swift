import Foundation
@testable import Nex
import Testing

struct MarkdownSourceMutationTests {
    @Test func insertsExactSelectionCommentAfterTargetBlock() throws {
        let markdown = "First paragraph.\n\nSecond paragraph.\n"
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "First paragraph.",
            anchorStrategy: .exactSelection,
            commentText: "Needs evidence.",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let firstRange = try #require(updated.range(of: "First paragraph."))
        let commentRange = try #require(updated.range(of: "<!-- nex-comment"))
        let secondRange = try #require(updated.range(of: "Second paragraph."))
        #expect(firstRange.lowerBound < commentRange.lowerBound)
        #expect(commentRange.lowerBound < secondRange.lowerBound)
        #expect(updated.contains("anchorStrategy: \"exact-selection\""))
        #expect(updated.contains("Needs evidence."))
    }

    @Test func insertsNearestBlockCommentAfterFallbackBlock() throws {
        let markdown = "# Heading\n\nParagraph.\n"
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "Heading\n\nParagraph.",
            anchorStrategy: .nearestBlock,
            commentText: "Spans blocks.",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let headingRange = try #require(updated.range(of: "# Heading"))
        let commentRange = try #require(updated.range(of: "<!-- nex-comment"))
        let paragraphRange = try #require(updated.range(of: "Paragraph."))
        #expect(headingRange.lowerBound < commentRange.lowerBound)
        #expect(commentRange.lowerBound < paragraphRange.lowerBound)
        #expect(updated.contains("anchorStrategy: \"nearest-block\""))
    }

    @Test func togglesUncheckedCheckedAndUppercaseMarkers() throws {
        let markdown = "- [ ] todo\n- [x] done\n- [X] loud\n"

        let first = try MarkdownSourceMutations.toggleTaskCheckbox(
            in: markdown,
            taskID: "task-1",
            checked: true
        ).markdown
        #expect(first.contains("- [x] todo"))

        let second = try MarkdownSourceMutations.toggleTaskCheckbox(
            in: markdown,
            taskID: "task-2",
            checked: false
        ).markdown
        #expect(second.contains("- [ ] done"))

        let third = try MarkdownSourceMutations.toggleTaskCheckbox(
            in: markdown,
            taskID: "task-3",
            checked: false
        ).markdown
        #expect(third.contains("- [ ] loud"))
    }

    @Test func togglePreservesIndentListMarkerLineEndingsAndTrailingNewlineAbsence() throws {
        let markdown = "Intro\r\n  * [ ] nested\r\nTail"
        let updated = try MarkdownSourceMutations.toggleTaskCheckbox(
            in: markdown,
            taskID: "task-1",
            checked: true
        ).markdown

        #expect(updated == "Intro\r\n  * [x] nested\r\nTail")
    }

    @Test func taskMarkerScanSkipsBlockquotedTaskLookingText() {
        let markdown = "> - [ ] quoted\n\n- [ ] real\n"
        let context = MarkdownRenderPipeline.makeContext(markdown)

        #expect(context.taskMarkers.count == 1)
        #expect(context.taskMarkers[0].sourceLine == 3)
    }
}
