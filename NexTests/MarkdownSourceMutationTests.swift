import Foundation
@testable import Nex
import Testing

struct MarkdownSourceMutationTests {
    @Test func insertsCommentAfterTargetBlock() throws {
        let markdown = "First paragraph.\n\nSecond paragraph.\n"
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "First paragraph.",
            commentText: "Needs evidence."
        )

        let firstRange = try #require(updated.range(of: "First paragraph."))
        let commentRange = try #require(updated.range(of: "<!--nx"))
        let secondRange = try #require(updated.range(of: "Second paragraph."))
        #expect(firstRange.lowerBound < commentRange.lowerBound)
        #expect(commentRange.lowerBound < secondRange.lowerBound)
        #expect(updated.contains(#"<!--nx "First paragraph.""#))
        #expect(updated.contains("Needs evidence."))
    }

    @Test func insertsCommentAfterFallbackBlock() throws {
        let markdown = "# Heading\n\nParagraph.\n"
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "Heading\n\nParagraph.",
            commentText: "Spans blocks."
        )

        let headingRange = try #require(updated.range(of: "# Heading"))
        let commentRange = try #require(updated.range(of: "<!--nx"))
        let paragraphRange = try #require(updated.range(of: "Paragraph."))
        #expect(headingRange.lowerBound < commentRange.lowerBound)
        #expect(commentRange.lowerBound < paragraphRange.lowerBound)
        #expect(updated.contains(#"<!--nx "Heading\n\nParagraph.""#))
    }

    @Test func insertCommentAtEOFPreservesTrailingNewlineAbsence() throws {
        let markdown = "Only paragraph."
        let updated = try MarkdownSourceMutations.insertComment(
            in: markdown,
            blockID: "block-1",
            selectedText: "Only paragraph.",
            commentText: "No final newline."
        )

        #expect(updated.contains("Only paragraph.\n\n<!--nx"))
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

    @Test func blockquotedTaskMarkerRendersAndTogglesOnlyRealTask() throws {
        let markdown = "> - [ ] quoted\n\n- [ ] real\n"
        let context = MarkdownRenderPipeline.makeContext(markdown)
        let html = MarkdownRenderer.renderToHTML(markdown)

        #expect(context.taskMarkers.count == 1)
        #expect(context.taskMarkers[0].sourceLine == 3)
        #expect(html.components(separatedBy: "data-nex-task-id=\"").count - 1 == 1)

        let updated = try MarkdownSourceMutations.toggleTaskCheckbox(
            in: markdown,
            taskID: context.taskMarkers[0].id,
            checked: true
        ).markdown
        #expect(updated == "> - [ ] quoted\n\n- [x] real\n")
    }

    @Test func taskMarkerScanIgnoresFenceTextInsideCommentBlocks() {
        let markdown = """
        Paragraph.

        <!--nx "Paragraph."
        ```
        -->

        - [ ] real
        """
        let context = MarkdownRenderPipeline.makeContext(markdown)

        #expect(context.taskMarkers.count == 1)
        #expect(context.taskMarkers[0].sourceLine == 7)
    }

    @Test func updatesCommentTextInPlacePreservingAnchor() throws {
        let markdown = """
        Paragraph.

        <!--nx "Paragraph."
        Old note.
        -->

        Tail.
        """
        let context = MarkdownRenderPipeline.makeContext(markdown)
        let commentID = try #require(context.comments.first?.id)

        let updated = try MarkdownSourceMutations.updateComment(
            in: markdown,
            commentID: commentID,
            commentText: "New note."
        )

        #expect(updated.contains("<!--nx \"Paragraph.\"\nNew note.\n-->"))
        #expect(!updated.contains("Old note."))
        #expect(updated.contains("Tail."))
    }

    @Test func deletesCommentBlockWithoutRemovingNeighbors() throws {
        let markdown = """
        Before.

        <!--nx "Before."
        Remove me.
        -->

        After.
        """
        let context = MarkdownRenderPipeline.makeContext(markdown)
        let commentID = try #require(context.comments.first?.id)

        let updated = try MarkdownSourceMutations.deleteComment(
            in: markdown,
            commentID: commentID
        )

        #expect(!updated.contains("<!--nx"))
        #expect(!updated.contains("Remove me."))
        #expect(updated.contains("Before."))
        #expect(updated.contains("After."))
        #expect(updated.contains("Before.\n\nAfter."))
        #expect(!updated.contains("Before.\n\n\nAfter."))
    }
}
