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

    @Test func insertCommentAtEOFPreservesTrailingNewlineAbsence() throws {
        let markdown = "Only paragraph."
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "Only paragraph.",
            anchorStrategy: .exactSelection,
            commentText: "No final newline.",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(updated.contains("Only paragraph.\n\n<!-- nex-comment"))
        #expect(!updated.hasSuffix("\n"))
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

    @Test func taskMarkerScanIgnoresFenceTextInsideCommentBlocks() {
        let markdown = """
        Paragraph.

        <!-- nex-comment
        id: "nex-fence"
        createdAt: "2026-05-15T00:00:00Z"
        anchorStrategy: "nearest-block"
        anchorText: |-
          Paragraph.
        comment: |-
          ```
        -->

        - [ ] real
        """
        let context = MarkdownRenderPipeline.makeContext(markdown)

        #expect(context.taskMarkers.count == 1)
        #expect(context.taskMarkers[0].sourceLine == 13)
    }

    @Test func updatesCommentTextInPlacePreservingAnchor() throws {
        let markdown = """
        Paragraph.

        <!-- nex-comment
        id: "nex-test"
        createdAt: "2026-05-15T00:00:00Z"
        anchorStrategy: "exact-selection"
        anchorText: |-
          Paragraph.
        comment: |-
          Old note.
        -->

        Tail.
        """

        let updated = try MarkdownSourceMutations.updateComment(
            in: markdown,
            commentID: "nex-test",
            commentText: "New note."
        )

        #expect(updated.contains("comment: |-\n  New note."))
        #expect(!updated.contains("Old note."))
        #expect(updated.contains("anchorText: |-\n  Paragraph."))
        #expect(updated.contains("Tail."))
    }

    @Test func deletesCommentBlockWithoutRemovingNeighbors() throws {
        let markdown = """
        Before.

        <!-- nex-comment
        id: "nex-delete"
        createdAt: "2026-05-15T00:00:00Z"
        anchorStrategy: "nearest-block"
        anchorText: |-
          Before.
        comment: |-
          Remove me.
        -->

        After.
        """

        let updated = try MarkdownSourceMutations.deleteComment(
            in: markdown,
            commentID: "nex-delete"
        )

        #expect(!updated.contains("<!-- nex-comment"))
        #expect(!updated.contains("Remove me."))
        #expect(updated.contains("Before."))
        #expect(updated.contains("After."))
        #expect(updated.contains("Before.\n\nAfter."))
        #expect(!updated.contains("Before.\n\n\nAfter."))
    }
}
