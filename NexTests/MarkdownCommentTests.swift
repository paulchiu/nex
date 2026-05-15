import Foundation
@testable import Nex
import Testing

struct MarkdownCommentTests {
    @Test func parsesValidCommentBlock() {
        let markdown = """
        Paragraph.

        <!--nx "Paragraph."
        Tighten this claim.
        -->
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].anchorText == "Paragraph.")
        #expect(scan.comments[0].comment == "Tighten this claim.")
        #expect(!scan.cleanedMarkdown.contains("<!--nx"))
    }

    @Test func malformedCommentIsHiddenAndRecordedSafely() {
        let markdown = """
        A.

        <!--nx "broken
        id: "broken"
        -->
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].isMalformed)
        #expect(scan.comments[0].comment == "Malformed Nex comment")
        #expect(!scan.cleanedMarkdown.contains("<!--nx"))
    }

    @Test func unclosedMalformedCommentDoesNotHideFollowingMarkdown() {
        let markdown = """
        A.

        <!--nx "broken"
        id: "broken"

        B.
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].isMalformed)
        #expect(!scan.cleanedMarkdown.contains("<!--nx"))
        #expect(scan.cleanedMarkdown.contains("id: \"broken\""))
        #expect(scan.cleanedMarkdown.contains("B."))
    }

    @Test func unknownHTMLCommentRemainsMarkdown() {
        let markdown = "A.\n\n<!-- ordinary -->\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!-- ordinary -->"))
    }

    @Test func unknownNxCommentWithoutQuotedAnchorRemainsMarkdown() {
        let markdown = "A.\n\n<!--nx ordinary -->\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!--nx ordinary -->"))
    }

    @Test func commentFieldsEscapeDashDashRoundTrip() {
        let empty = ""
        let original = MarkdownComment(
            id: "nex-test",
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

    @Test func commentAnchorRoundTripsEmbeddedQuote() {
        let empty = ""
        let original = MarkdownComment(
            id: "nex-test",
            anchorText: #"quoted "anchor""#,
            comment: "note",
            markerRange: empty.startIndex ..< empty.startIndex
        )
        let serialized = MarkdownCommentParser.serialize(original, lineEnding: "\n")
        let markdown = "A.\n\n\(serialized)\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments[0].anchorText == #"quoted "anchor""#)
    }

    @Test func commentAnchorRoundTripsMultilineSelection() {
        let empty = ""
        let original = MarkdownComment(
            id: "nex-test",
            anchorText: "line one\nline two",
            comment: "note",
            markerRange: empty.startIndex ..< empty.startIndex
        )
        let serialized = MarkdownCommentParser.serialize(original, lineEnding: "\n")
        let markdown = "A.\n\n\(serialized)\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(serialized.contains(#"<!--nx "line one\nline two""#))
        #expect(scan.comments[0].anchorText == "line one\nline two")
    }

    @Test func parsesCRLFCommentBlockWithoutInjectedBlankLines() {
        let markdown = [
            "Paragraph.",
            "",
            "<!--nx \"Paragraph.\"",
            "Tighten this claim.",
            "-->",
            ""
        ].joined(separator: "\r\n")
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.count == 1)
        #expect(scan.comments[0].anchorText == "Paragraph.")
        #expect(scan.comments[0].comment == "Tighten this claim.")
    }

    @Test func runtimeCommentIDIsDeterministicAcrossScans() throws {
        let markdown = """
        Paragraph.

        <!--nx "Paragraph."
        Tighten this claim.
        -->
        """
        let first = try #require(MarkdownRenderPipeline.makeContext(markdown).comments.first)
        let second = try #require(MarkdownRenderPipeline.makeContext(markdown).comments.first)

        #expect(first.id == second.id)
        #expect(first.id.hasPrefix("c-"))
        #expect(first.id.count == 10)
    }

    @Test func commentInsideFenceIsNotParsed() {
        let markdown = """
        ```
        <!--nx "nope"
        note
        -->
        ```
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!--nx"))
    }

    @Test func indentedCommentLookalikeIsNotParsed() {
        let markdown = """
            <!--nx "code"
            note
            -->

        Paragraph.
        """
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown.contains("<!--nx"))
        #expect(scan.cleanedMarkdown.contains("note"))
    }

    @Test func inlineAdjacentCommentLookalikeIsNotStripped() {
        let markdown = "Paragraph <!--nx \"still prose\" -->\n"
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)

        #expect(scan.comments.isEmpty)
        #expect(scan.cleanedMarkdown == markdown)
    }

    @Test func parsesAddCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "addComment",
            "selectedText": "  Selected text.  ",
            "blockID": "block-1",
            "comment": "  New note.  "
        ])

        guard case let .addComment(selectedText, blockID, comment) = payload else {
            Issue.record("expected addComment payload")
            return
        }
        #expect(selectedText == "  Selected text.  ")
        #expect(blockID == "block-1")
        #expect(comment == "New note.")
    }

    @Test func parsesRequestAddCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "requestAddComment",
            "selectedText": "Selected text.",
            "blockID": "block-1",
            "rect": ["x": 10, "y": 20, "width": 30, "height": 12]
        ])

        guard case let .requestAddComment(selectedText, blockID, anchorRect) = payload else {
            Issue.record("expected requestAddComment payload")
            return
        }
        #expect(selectedText == "Selected text.")
        #expect(blockID == "block-1")
        #expect(anchorRect == .init(x: 10, y: 20, width: 30, height: 12))
    }

    @Test func parsesRequestEditCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "requestEditComment",
            "commentID": "nex-test",
            "comment": "Existing note.",
            "rect": ["x": 11.5, "y": 21.5, "width": 31.5, "height": 13.5]
        ])

        guard case let .requestEditComment(commentID, comment, anchorRect) = payload else {
            Issue.record("expected requestEditComment payload")
            return
        }
        #expect(commentID == "nex-test")
        #expect(comment == "Existing note.")
        #expect(anchorRect == .init(x: 11.5, y: 21.5, width: 31.5, height: 13.5))
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

    @Test func parsesRequestDeleteCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "requestDeleteComment",
            "commentID": "nex-test",
            "rect": ["x": 1, "y": 2, "width": 3, "height": 4]
        ])

        guard case let .requestDeleteComment(commentID, anchorRect) = payload else {
            Issue.record("expected requestDeleteComment payload")
            return
        }
        #expect(commentID == "nex-test")
        #expect(anchorRect == .init(x: 1, y: 2, width: 3, height: 4))
    }

    @Test func parsesActivateCommentReviewPayload() {
        let payload = MarkdownReviewPayload.parse([
            "type": "activateComment",
            "commentID": "nex-test",
            "scrollTarget": true
        ])

        guard case let .activateComment(commentID, scrollTarget, scrollCard) = payload else {
            Issue.record("expected activateComment payload")
            return
        }
        #expect(commentID == "nex-test")
        #expect(scrollTarget)
        #expect(!scrollCard)
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

    @Test func reviewScriptRequestsSwiftOwnedCommentPopovers() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("type: 'requestAddComment'"))
        #expect(source.contains("type: 'requestEditComment'"))
        #expect(source.contains("type: 'requestDeleteComment'"))
        #expect(source.contains("function rectPayload(rect)"))
        #expect(!source.contains("document.createElement('textarea')"))
        #expect(!source.contains("function showPopover"))
        #expect(!source.contains("function showEditPopover"))
        #expect(!source.contains("function showDeletePopover"))
    }

    @Test func reviewScriptExposesSwiftCommentStateAdapters() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("ns.setActiveComment = function(id, options)"))
        #expect(source.contains("ns.clearSelection = function()"))
        #expect(source.contains("ns.showError = function(message)"))
        #expect(!source.contains("function onPopoverKeyDown(event)"))
    }

    @Test func reviewScriptPostsSelectionGeometryToSwift() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("rect: rectPayload(range.getBoundingClientRect())"))
        #expect(source.contains("rect: rectPayload(editCard.getBoundingClientRect())"))
        #expect(source.contains("rect: rectPayload(deleteCard.getBoundingClientRect())"))
    }

    @Test func reviewScriptPositionsCommentCardsByAnchor() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("function positionCommentCards()"))
        #expect(source.contains("targetForCommentCard(card)"))
        #expect(source.contains("target.getBoundingClientRect().top - railRect.top"))
        #expect(source.contains("nex-comment-rail-positioned"))
        #expect(source.contains("window.addEventListener('resize', scheduleCommentLayout)"))
        #expect(source.contains("new ResizeObserver(scheduleCommentLayout)"))
        #expect(source.contains("document.fonts.ready.then(scheduleCommentLayout)"))
        #expect(source.contains("window.addEventListener('load', scheduleCommentLayout)"))
    }

    @Test func reviewScriptActivatesFocusedCommentCardsFromKeyboard() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("function onKeyDown(event)"))
        #expect(source.contains("event.key !== 'Enter'"))
        #expect(source.contains("event.key !== ' '"))
        #expect(source.contains("type: 'activateComment'"))
        #expect(source.contains("scrollTarget: true"))
        #expect(source.contains("document.addEventListener('keydown', onKeyDown, true)"))
    }

    @Test func reviewScriptCanHighlightAnchorTextAcrossInlineNodes() {
        let source = MarkdownReviewScript.source

        #expect(source.contains("function uniqueTextRange(nodes, anchor)"))
        #expect(source.contains("function wrapTextRange(range, id)"))
        #expect(source.contains("function wrapTextNodeSegment(node, start, end, id)"))
        #expect(!source.contains("nodes[n].nodeValue.indexOf(anchor)"))
    }

    @Test func findScriptSkipsCommentHighlightedText() {
        let source = MarkdownFindScript.source

        #expect(source.contains("classList.contains('\(MarkdownDOMClass.commentRail)')"))
        #expect(source.contains("classList.contains('\(MarkdownDOMClass.commentHighlight)')"))
    }
}
