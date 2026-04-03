import Foundation
@testable import Nex
import Testing

struct MarkdownHTMLRendererTests {
    // MARK: - @ mentions

    @Test func atMentionMidSentence() {
        let html = MarkdownRenderer.renderToHTML("Hello @claude how are you")
        #expect(html.contains("@claude"))
    }

    @Test func atMentionAtStartOfLine() {
        let html = MarkdownRenderer.renderToHTML("@claude please review this")
        #expect(html.contains("@claude"))
    }

    @Test func atMentionInListItem() {
        let html = MarkdownRenderer.renderToHTML("- assign to @claude")
        #expect(html.contains("@claude"))
    }

    @Test func atMentionStandaloneOnLine() {
        let html = MarkdownRenderer.renderToHTML("@claude")
        #expect(html.contains("@claude"))
    }

    // MARK: - Basic rendering sanity

    @Test func headingRendered() {
        let html = MarkdownRenderer.renderToHTML("# Title")
        #expect(html.contains("<h1>Title</h1>"))
    }

    @Test func paragraphRendered() {
        let html = MarkdownRenderer.renderToHTML("Hello world")
        #expect(html.contains("<p>Hello world</p>"))
    }
}
