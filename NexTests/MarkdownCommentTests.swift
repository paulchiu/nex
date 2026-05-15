import Foundation
@testable import Nex
import Testing

struct MarkdownCommentTests {
    @Test func parsesValidCommentBlock() {
        let markdown = """
        Paragraph.

        <!-- nex-comment
        id: "nex-test"
        createdAt: "2026-05-15T00:00:00Z"
        anchorStrategy: "exact-selection"
        anchorText: |-
          Paragraph.
        comment: |-
          Tighten this claim.
        -->
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].id == "nex-test")
        #expect(scan.comments[0].anchorStrategy == .exactSelection)
        #expect(scan.comments[0].anchorText == "Paragraph.")
        #expect(scan.comments[0].comment == "Tighten this claim.")
        #expect(!scan.cleanedMarkdown.contains("<!-- nex-comment"))
    }

    @Test func malformedCommentIsHiddenAndRecordedSafely() {
        let markdown = """
        A.

        <!-- nex-comment
        id: "broken"
        -->
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].isMalformed)
        #expect(scan.comments[0].comment == "Malformed Nex comment")
        #expect(!scan.cleanedMarkdown.contains("<!-- nex-comment"))
    }

    @Test func unknownHTMLCommentRemainsMarkdown() {
        let markdown = "A.\n\n<!-- ordinary -->\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!-- ordinary -->"))
    }

    @Test func commentFieldsEscapeDashDashRoundTrip() {
        let empty = ""
        let original = MarkdownComment(
            id: "nex-test",
            createdAt: Date(timeIntervalSince1970: 0),
            anchorStrategy: .exactSelection,
            anchorText: "a -- b --> c",
            comment: "note -- with --> marker",
            markerRange: empty.startIndex ..< empty.startIndex
        )
        let serialized = MarkdownCommentParser.serialize(original, lineEnding: "\n")
        let middle = serialized.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")

        #expect(!middle.contains("--"))

        let markdown = "A.\n\n\(serialized)\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments[0].anchorText == "a -- b --> c")
        #expect(scan.comments[0].comment == "note -- with --> marker")
    }

    @Test func commentInsideFenceIsNotParsed() {
        let markdown = """
        ```
        <!-- nex-comment
        id: "nope"
        -->
        ```
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!-- nex-comment"))
    }

    @Test func inlineAdjacentCommentLookalikeIsNotStripped() {
        let markdown = "Paragraph <!-- nex-comment still prose -->\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown == markdown)
    }

    @Test func parsesUpdateCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "updateComment",
            "commentID": "nex-test",
            "comment": "  Updated.  "
        ])

        guard case let .updateComment(commentID, comment) = payload else {
            Issue.record("expected updateComment payload")
            return
        }
        #expect(commentID == "nex-test")
        #expect(comment == "Updated.")
    }

    @Test func parsesDeleteCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "deleteComment",
            "commentID": "nex-test"
        ])

        guard case let .deleteComment(commentID) = payload else {
            Issue.record("expected deleteComment payload")
            return
        }
        #expect(commentID == "nex-test")
    }

    @Test func rejectsBlankUpdateCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "updateComment",
            "commentID": "nex-test",
            "comment": "  \n  "
        ])

        if payload != nil {
            Issue.record("expected blank update comment payload to be rejected")
        }
    }

    @Test func reviewScriptSubmitsCommentTextareaOnCommandEnter() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("function isCommandEnter(event)"))
        #expect(source.contains("event.metaKey"))
        #expect(source.contains("event.key === 'Enter' || event.key === 'NumpadEnter'"))
        #expect(source.contains("textarea.addEventListener('keydown'"))
        #expect(source.contains("submitComment();"))
    }

    @Test func reviewScriptPositionsCommentCardsByAnchor() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("function positionCommentCards()"))
        #expect(source.contains("targetForCommentCard(card)"))
        #expect(source.contains("target.getBoundingClientRect().top - railRect.top"))
        #expect(source.contains("nex-comment-rail-positioned"))
        #expect(source.contains("window.addEventListener('resize', positionCommentCards)"))
    }
}
