import AppKit
import Foundation
import Markdown

/// Converts a swift-markdown AST into HTML.
struct MarkdownHTMLRenderer: MarkupVisitor {
    typealias Result = String

    private static let urlDetector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Only auto-link matches whose source text starts with one of these
    /// schemes. NSDataDetector also matches schemeless domains like
    /// `example.com` and bare emails like `foo@example.com`, which we
    /// deliberately leave as plain text — terminal-style "make pasted
    /// URLs clickable" behaviour, not GitHub-style fuzzy linkification.
    private static let allowedSchemePrefixes: [String] = [
        "http://", "https://", "ftp://", "file://", "mailto:"
    ]

    private var isInTableHead = false
    private var skipAutolinkDepth = 0
    private var context: MarkdownRenderContext?
    private var blockCursor = 0

    init(context: MarkdownRenderContext? = nil) {
        self.context = context
    }

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined()
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let block = nextBlock()
        let content = heading.children.map { visit($0) }.joined()
        return "<h\(heading.level)\(blockAttributes(for: block))>\(content)</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let block = nextBlock()
        let content = paragraph.children.map { visit($0) }.joined()
        return "<p\(blockAttributes(for: block))>\(content)</p>\n"
    }

    mutating func visitText(_ text: Text) -> String {
        if skipAutolinkDepth > 0 {
            return escapeHTML(text.string)
        }
        return autolinkText(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let content = emphasis.children.map { visit($0) }.joined()
        return "<em>\(content)</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let content = strong.children.map { visit($0) }.joined()
        return "<strong>\(content)</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let content = strikethrough.children.map { visit($0) }.joined()
        return "<del>\(content)</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let block = nextBlock()
        let lang = codeBlock.language ?? ""
        let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
        let code = escapeHTML(codeBlock.code)
        return "<pre\(blockAttributes(for: block))><code\(langAttr)>\(code)</code></pre>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        let items = list.children.map { visit($0) }.joined()
        return "<ul>\n\(items)</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex
        let startAttr = start != 1 ? " start=\"\(start)\"" : ""
        let items = list.children.map { visit($0) }.joined()
        return "<ol\(startAttr)>\n\(items)</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        let block = nextBlock()
        let taskMarker = item.checkbox == nil ? nil : taskMarker(for: item)
        let content = item.children.map { visit($0) }.joined()
        if let checkbox = item.checkbox {
            let checkedAttr = checkbox == .checked ? " checked" : ""
            let inputAttrs = if let taskMarker {
                " data-nex-task-id=\"\(escapeHTML(taskMarker.id))\"\(checkedAttr)"
            } else {
                "\(checkedAttr) disabled"
            }
            return "<li\(blockAttributes(for: block, classes: ["task-list-item"]))>"
                + "<input type=\"checkbox\" class=\"task-list-item-checkbox\"\(inputAttrs)> "
                + "\(content)</li>\n"
        }
        return "<li\(blockAttributes(for: block))>\(content)</li>\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        skipAutolinkDepth += 1
        let content = link.children.map { visit($0) }.joined()
        skipAutolinkDepth -= 1
        let dest = escapeHTML(link.destination ?? "")
        return "<a href=\"\(dest)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        skipAutolinkDepth += 1
        let alt = image.children.map { visit($0) }.joined()
        skipAutolinkDepth -= 1
        let src = escapeHTML(image.source ?? "")
        let titleAttr = image.title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
        return "<img src=\"\(src)\" alt=\"\(alt)\"\(titleAttr)>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let block = nextBlock()
        let content = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote\(blockAttributes(for: block))>\n\(content)</blockquote>\n"
    }

    mutating func visitThematicBreak(_: ThematicBreak) -> String {
        let block = nextBlock()
        return "<hr\(blockAttributes(for: block))>\n"
    }

    mutating func visitSoftBreak(_: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        html.rawHTML
    }

    // MARK: - GFM Tables

    mutating func visitTable(_ table: Table) -> String {
        let block = nextBlock()
        let content = table.children.map { visit($0) }.joined()
        return "<table\(blockAttributes(for: block))>\n\(content)</table>\n"
    }

    mutating func visitTableHead(_ head: Table.Head) -> String {
        isInTableHead = true
        let content = head.children.map { visit($0) }.joined()
        isInTableHead = false
        return "<thead>\n\(content)</thead>\n"
    }

    mutating func visitTableBody(_ body: Table.Body) -> String {
        let content = body.children.map { visit($0) }.joined()
        return "<tbody>\n\(content)</tbody>\n"
    }

    mutating func visitTableRow(_ row: Table.Row) -> String {
        let content = row.children.map { visit($0) }.joined()
        return "<tr>\(content)</tr>\n"
    }

    mutating func visitTableCell(_ cell: Table.Cell) -> String {
        let block = nextBlock()
        let content = cell.children.map { visit($0) }.joined()
        let tag = isInTableHead ? "th" : "td"
        return "<\(tag)\(blockAttributes(for: block))>\(content)</\(tag)>"
    }

    // MARK: - Helpers

    private mutating func nextBlock() -> MarkdownSourceBlock? {
        guard let context, blockCursor < context.sourceBlocks.count else { return nil }
        let block = context.sourceBlocks[blockCursor]
        blockCursor += 1
        return block
    }

    private func taskMarker(for item: ListItem) -> MarkdownTaskMarker? {
        guard let context,
              let sourceRange = item.range,
              let itemRange = context.sourceMap.range(for: sourceRange)
        else { return nil }
        return context.taskMarkersByItemRange[itemRange]
    }

    private func blockAttributes(
        for block: MarkdownSourceBlock?,
        classes: [String] = []
    ) -> String {
        guard let block else {
            if classes.isEmpty { return "" }
            return " class=\"\(classes.joined(separator: " "))\""
        }

        var allClasses = classes
        if let context, context.commentsByBlockID[block.id]?.isEmpty == false {
            allClasses.append(MarkdownDOMClass.commentBlock)
        }

        var attributes = " data-nex-block-id=\"\(escapeHTML(block.id))\""
        if !allClasses.isEmpty {
            attributes = " class=\"\(allClasses.joined(separator: " "))\"" + attributes
        }
        return attributes
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Wrap any URLs detected in plain text with `<a>` tags so bare links
    /// (e.g. `https://example.com`) are clickable, matching terminal behaviour.
    /// swift-markdown only auto-detects `<>`-wrapped URLs and `[text](url)`
    /// syntax — bare URLs in text reach us as plain `Text` nodes.
    private func autolinkText(_ text: String) -> String {
        guard let detector = Self.urlDetector else {
            return escapeHTML(text)
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = detector.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else {
            return escapeHTML(text)
        }
        var result = ""
        var cursor = 0
        for match in matches {
            let urlText = nsText.substring(with: match.range)
            let lower = urlText.lowercased()
            let hasAllowedScheme = Self.allowedSchemePrefixes.contains(where: lower.hasPrefix)
            // Skip schemeless domains and bare emails — let them render as
            // plain text so they fall through into the surrounding escape.
            guard hasAllowedScheme else { continue }
            if match.range.location > cursor {
                let preLen = match.range.location - cursor
                result += escapeHTML(nsText.substring(with: NSRange(location: cursor, length: preLen)))
            }
            let href = match.url?.absoluteString ?? urlText
            result += "<a href=\"\(escapeHTML(href))\">\(escapeHTML(urlText))</a>"
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            let tailLen = nsText.length - cursor
            result += escapeHTML(nsText.substring(with: NSRange(location: cursor, length: tailLen)))
        }
        return result
    }
}

// MARK: - Public API

enum MarkdownRenderer {
    /// Parse markdown text and return a full HTML document string.
    static func renderToHTML(
        _ markdown: String,
        backgroundColor: NSColor = .windowBackgroundColor,
        backgroundOpacity: Double = 1.0,
        reviewAccentColor: NSColor = .controlAccentColor,
        baseFontSize: Double = 14
    ) -> String {
        let yaml = MarkdownRenderPipeline.frontMatter(in: markdown)
        let context = MarkdownRenderPipeline.makeContext(markdown)
        var visitor = MarkdownHTMLRenderer(context: context)
        let bodyHTML = visitor.visit(context.document)
        let fmHTML = yaml.map(FrontMatterRenderer.render) ?? ""
        let commentRailHTML = renderCommentRail(context)
        let bgCSS = cssBackground(color: backgroundColor, opacity: backgroundOpacity)
        let isDark = isDarkBackground(color: backgroundColor)
        return wrapInHTMLDocument(
            fmHTML + bodyHTML,
            commentRailHTML: commentRailHTML,
            backgroundCSS: bgCSS,
            reviewAccentCSS: reviewAccentCSS(
                accentColor: reviewAccentColor,
                backgroundColor: backgroundColor,
                isDark: isDark
            ),
            isDark: isDark,
            baseFontSize: baseFontSize
        )
    }

    private static func renderCommentRail(_ context: MarkdownRenderContext) -> String {
        guard !context.comments.isEmpty else { return "" }
        var cards = ""
        for comment in context.comments {
            let blockID = context.commentBlockIDs[comment.id] ?? ""
            let malformedClass = comment.isMalformed ? " nex-comment-card-malformed" : ""
            let editButton = comment.isMalformed ? "" : """
            <button type="button" class="nex-comment-action" data-nex-comment-edit aria-label="Edit comment" title="Edit comment">\(commentEditIcon)</button>
            """
            cards += """
            <article class="nex-comment-card\(malformedClass)" tabindex="0" data-nex-comment-id="\(escapeHTML(comment.id))" data-nex-comment-block-id="\(escapeHTML(blockID))" data-nex-anchor-text="\(escapeHTMLAttribute(comment.anchorText))">
            <header class="nex-comment-card-header">
            <div class="nex-comment-card-label">Comment</div>
            <div class="nex-comment-actions">
            \(editButton)
            <button type="button" class="nex-comment-action nex-comment-delete" data-nex-comment-delete aria-label="Delete comment" title="Delete comment">\(commentDeleteIcon)</button>
            </div>
            </header>
            <p data-nex-comment-body>\(escapeHTML(comment.comment))</p>
            </article>

            """
        }
        return """
        <aside class="\(MarkdownDOMClass.commentRail)" aria-label="Comments">
        \(cards)</aside>
        """
    }

    private static let commentEditIcon = """
    <svg class="nex-comment-action-icon" aria-hidden="true" viewBox="0 0 16 16" focusable="false">
    <path d="M3.5 11.5 3 13l1.5-.5 7.35-7.35a1.15 1.15 0 0 0-1.63-1.63L3.5 10.25v1.25Z"/>
    <path d="m9.5 4.25 2.25 2.25"/>
    </svg>
    """

    private static let commentDeleteIcon = """
    <svg class="nex-comment-action-icon" aria-hidden="true" viewBox="0 0 16 16" focusable="false">
    <path d="M5.25 4.5V3.75A1.25 1.25 0 0 1 6.5 2.5h3a1.25 1.25 0 0 1 1.25 1.25v.75"/>
    <path d="M3.75 4.5h8.5"/>
    <path d="m5 6 .45 6.25a1.25 1.25 0 0 0 1.25 1.15h2.6a1.25 1.25 0 0 0 1.25-1.15L11 6"/>
    </svg>
    """

    private static func isDarkBackground(color: NSColor) -> Bool {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance < 0.5
    }

    private static func cssBackground(color: NSColor, opacity: Double) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return "background-color: rgba(\(r), \(g), \(b), \(opacity));"
    }

    private static func reviewAccentCSS(
        accentColor: NSColor,
        backgroundColor: NSColor,
        isDark: Bool
    ) -> String {
        let accent = usableReviewAccent(
            accentColor,
            backgroundColor: backgroundColor,
            isDark: isDark
        )
        let strongAccent = mix(
            accent,
            with: isDark ? .white : .black,
            amount: isDark ? 0.28 : 0.18
        )

        return """
        --nex-comment-accent: \(cssHex(accent));
        --nex-comment-accent-strong: \(cssHex(strongAccent));
        --nex-comment-block-bg: \(cssRGBA(accent, alpha: isDark ? 0.16 : 0.10));
        --nex-comment-block-active-bg: \(cssRGBA(accent, alpha: isDark ? 0.34 : 0.22));
        --nex-comment-card-bg: \(cssRGBA(accent, alpha: isDark ? 0.14 : 0.08));
        --nex-comment-card-active-bg: \(cssRGBA(accent, alpha: isDark ? 0.30 : 0.18));
        --nex-comment-highlight-bg: \(cssRGBA(accent, alpha: isDark ? 0.40 : 0.32));
        --nex-comment-highlight-active-bg: \(cssRGBA(strongAccent, alpha: isDark ? 0.72 : 0.58));
        --nex-comment-ring: \(cssRGBA(strongAccent, alpha: isDark ? 0.56 : 0.42));
        """
    }

    private static func usableReviewAccent(
        _ color: NSColor,
        backgroundColor: NSColor,
        isDark: Bool
    ) -> NSColor {
        let fallback = NSColor.systemBlue.usingColorSpace(.sRGB)
            ?? NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        var candidate = color.usingColorSpace(.sRGB) ?? fallback
        let background = backgroundColor.usingColorSpace(.sRGB) ?? (isDark ? .black : .white)
        let target = isDark ? NSColor.white : NSColor.black

        guard contrastRatio(candidate, background) < 1.8 else { return candidate }
        for amount in [0.25, 0.4, 0.55, 0.7] {
            candidate = mix(candidate, with: target, amount: amount)
            if contrastRatio(candidate, background) >= 1.8 {
                return candidate
            }
        }
        return candidate
    }

    private static func cssHex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02x%02x%02x",
            clampedColorByte(rgb.redComponent),
            clampedColorByte(rgb.greenComponent),
            clampedColorByte(rgb.blueComponent)
        )
    }

    private static func cssRGBA(_ color: NSColor, alpha: Double) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "rgba(%d, %d, %d, %.2f)",
            clampedColorByte(rgb.redComponent),
            clampedColorByte(rgb.greenComponent),
            clampedColorByte(rgb.blueComponent),
            min(max(alpha, 0), 1)
        )
    }

    private static func clampedColorByte(_ component: CGFloat) -> Int {
        min(max(Int((component * 255).rounded()), 0), 255)
    }

    private static func mix(_ color: NSColor, with other: NSColor, amount: CGFloat) -> NSColor {
        let first = color.usingColorSpace(.sRGB) ?? color
        let second = other.usingColorSpace(.sRGB) ?? other
        let amount = min(max(amount, 0), 1)
        let inverse = 1 - amount
        return NSColor(
            red: first.redComponent * inverse + second.redComponent * amount,
            green: first.greenComponent * inverse + second.greenComponent * amount,
            blue: first.blueComponent * inverse + second.blueComponent * amount,
            alpha: 1.0
        )
    }

    private static func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> Double {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    private static func wrapInHTMLDocument(
        _ body: String,
        commentRailHTML: String,
        backgroundCSS: String,
        reviewAccentCSS: String,
        isDark: Bool,
        baseFontSize: Double
    ) -> String {
        let layoutClass = commentRailHTML.isEmpty
            ? "nex-review-layout"
            : "nex-review-layout nex-has-comment-rail"
        return """
        <!DOCTYPE html>
        <html class="\(isDark ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css(backgroundCSS: backgroundCSS, reviewAccentCSS: reviewAccentCSS, baseFontSize: baseFontSize))
        </style>
        </head>
        <body>
        <div id="content" class="\(layoutClass)">
        <main class="nex-markdown-main">
        \(body)
        </main>
        \(commentRailHTML)
        </div>
        </body>
        </html>
        """
    }

    // MARK: - Stylesheet

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\n", with: "&#10;")
    }

    private static func css(
        backgroundCSS: String,
        reviewAccentCSS: String,
        baseFontSize: Double
    ) -> String {
        let codeFontSize = max(baseFontSize - 1, 6)
        return """
        :root {
            \(reviewAccentCSS)
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
            font-size: \(baseFontSize)px;
            line-height: 1.6;
            padding: 20px 28px;
            margin: 0;
            color: #1f2328;
            \(backgroundCSS)
        }
        .dark body { color: #e6edf3; }
        .nex-review-layout {
            width: 100%;
        }
        .nex-review-layout.nex-has-comment-rail {
            display: grid;
            grid-template-columns: minmax(0, 1fr) minmax(112px, 32%);
            gap: 10px;
            align-items: start;
        }
        .nex-markdown-main {
            min-width: 0;
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            font-weight: 600;
        }
        h1 { font-size: 2em; border-bottom: 1px solid #d1d9e0; padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid #d1d9e0; padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        .dark h1, .dark h2 { border-bottom-color: #3d444d; }
        p { margin: 0.5em 0 1em; }
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .dark a { color: #58a6ff; }
        pre {
            background: #f6f8fa;
            padding: 16px;
            border-radius: 6px;
            overflow-x: auto;
            font-size: \(codeFontSize)px;
            line-height: 1.45;
        }
        .dark pre { background: #161b22; }
        code {
            font-family: 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 0.9em;
        }
        :not(pre) > code {
            background: #eff1f3;
            padding: 2px 6px;
            border-radius: 4px;
        }
        .dark :not(pre) > code { background: #262c36; }
        blockquote {
            border-left: 4px solid #d1d9e0;
            padding: 0 16px;
            color: #656d76;
            margin: 0.5em 0 1em;
        }
        .dark blockquote { border-left-color: #3d444d; color: #9198a1; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 0.5em 0 1em;
        }
        th, td {
            border: 1px solid #d1d9e0;
            padding: 8px 12px;
            text-align: left;
        }
        th { font-weight: 600; background: #f6f8fa; }
        .dark th, .dark td { border-color: #3d444d; }
        .dark th { background: #161b22; }
        ul, ol { padding-left: 2em; margin: 0.5em 0; }
        li { margin: 0.25em 0; }
        li.task-list-item { list-style-type: none; }
        /* -1.4em pulls the checkbox into the bullet column. Assumes
           `ul, ol { padding-left: 2em }` above. Native disabled checkboxes
           render very faintly, so we draw our own GitHub-style box. */
        li.task-list-item > input.task-list-item-checkbox {
            appearance: none;
            -webkit-appearance: none;
            width: 14px;
            height: 14px;
            border: 1.5px solid #8c959f;
            border-radius: 3px;
            background: transparent;
            margin: 0 0.4em 0.15em -1.4em;
            vertical-align: middle;
            cursor: pointer;
        }
        li.task-list-item > input.task-list-item-checkbox:disabled { cursor: default; }
        .dark li.task-list-item > input.task-list-item-checkbox {
            border-color: #7d8590;
        }
        li.task-list-item > input.task-list-item-checkbox:checked {
            background-color: #1f6feb;
            border-color: #1f6feb;
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3 8l3 3 7-7' stroke='white' stroke-width='2' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: center;
            background-size: 12px 12px;
        }
        /* Inline the leading paragraph so it sits beside the checkbox.
           Vertical margins drop on inline elements, so trailing block <p>s
           in loose lists still get their own top margin. */
        li.task-list-item > p:first-of-type { display: inline; }
        hr {
            border: none;
            border-top: 1px solid #d1d9e0;
            margin: 2em 0;
        }
        .dark hr { border-top-color: #3d444d; }
        img { max-width: 100%; border-radius: 4px; }
        del { color: #656d76; }
        .dark del { color: #9198a1; }
        table.frontmatter {
            margin: 0 0 1.5em;
            border: 1px solid #d1d9e0;
            border-radius: 6px;
            border-collapse: separate;
            border-spacing: 0;
            width: auto;
            min-width: 40%;
            max-width: 100%;
            font-size: 0.9em;
            overflow: hidden;
        }
        .dark table.frontmatter { border-color: #3d444d; }
        table.frontmatter th,
        table.frontmatter td {
            border: none;
            border-bottom: 1px solid #d1d9e0;
            padding: 6px 12px;
            text-align: start;
            vertical-align: top;
        }
        .dark table.frontmatter th,
        .dark table.frontmatter td { border-bottom-color: #3d444d; }
        table.frontmatter tr:last-child th,
        table.frontmatter tr:last-child td { border-bottom: none; }
        table.frontmatter th {
            font-weight: 600;
            color: #656d76;
            background: #f6f8fa;
            white-space: nowrap;
            width: 1%;
        }
        .dark table.frontmatter th { background: #161b22; color: #9198a1; }
        table.frontmatter td {
            font-family: 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 0.95em;
            word-break: break-word;
        }
        pre.frontmatter-raw,
        pre.frontmatter-nested {
            margin: 0;
            padding: 8px 10px;
            background: transparent;
            border: none;
            font-size: 0.85em;
            white-space: pre-wrap;
        }
        pre.frontmatter-raw {
            border-left: 3px solid #d1d9e0;
            padding-left: 10px;
            margin: 0 0 1.5em;
        }
        .dark pre.frontmatter-raw { border-left-color: #3d444d; }
        .\(MarkdownDOMClass.commentBlock) {
            background: var(--nex-comment-block-bg);
            box-shadow: inset 3px 0 0 var(--nex-comment-accent);
            padding-left: 8px;
            margin-left: -8px;
        }
        .\(MarkdownDOMClass.commentBlockActive) {
            background: var(--nex-comment-block-active-bg);
            box-shadow: inset 4px 0 0 var(--nex-comment-accent-strong), 0 0 0 1px var(--nex-comment-ring);
        }
        .\(MarkdownDOMClass.commentHighlight) {
            background: var(--nex-comment-highlight-bg);
            border-radius: 2px;
            box-decoration-break: clone;
            -webkit-box-decoration-break: clone;
        }
        .\(MarkdownDOMClass.commentHighlightActive) {
            background: var(--nex-comment-highlight-active-bg);
            box-shadow: 0 0 0 1px var(--nex-comment-ring);
        }
        .\(MarkdownDOMClass.commentRail) {
            position: relative;
            align-self: stretch;
            min-height: calc(100vh - 40px);
            overflow: visible;
            padding-left: 10px;
            border-left: 1px solid #d1d9e0;
            display: grid;
            gap: 8px;
            align-content: start;
            -webkit-user-select: none;
            user-select: none;
        }
        .dark .\(MarkdownDOMClass.commentRail) { border-left-color: #3d444d; }
        .\(MarkdownDOMClass.commentRail).nex-comment-rail-positioned {
            display: block;
        }
        .nex-comment-card {
            border: 1px solid var(--nex-comment-accent);
            background: var(--nex-comment-card-bg);
            padding: 8px;
            border-radius: 6px;
            cursor: pointer;
            position: relative;
            box-sizing: border-box;
        }
        .\(MarkdownDOMClass.commentRail).nex-comment-rail-positioned .nex-comment-card {
            position: absolute;
            left: 10px;
            right: 0;
        }
        .nex-comment-card:focus-visible,
        .nex-comment-card.\(MarkdownDOMClass.commentCardActive) {
            border-color: var(--nex-comment-accent-strong);
            outline: none;
            background: var(--nex-comment-card-active-bg);
        }
        .nex-comment-card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 6px;
            margin-bottom: 4px;
        }
        .nex-comment-card-label {
            color: #656d76;
            font-size: 0.78em;
            font-weight: 600;
        }
        .dark .nex-comment-card-label { color: #9198a1; }
        .nex-comment-actions {
            display: flex;
            gap: 3px;
            margin-left: auto;
            opacity: 0;
            pointer-events: none;
            transition: opacity 120ms ease;
        }
        .nex-comment-card:hover .nex-comment-actions,
        .nex-comment-card:focus-within .nex-comment-actions {
            opacity: 1;
            pointer-events: auto;
        }
        .nex-comment-action {
            border: 1px solid #d1d9e0;
            border-radius: 4px;
            background: rgba(255, 255, 255, 0.42);
            color: #57606a;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 20px;
            height: 20px;
            padding: 0;
        }
        .nex-comment-action:hover,
        .nex-comment-action:focus-visible {
            border-color: #d1d9e0;
            background: rgba(175, 184, 193, 0.18);
            color: #1f2328;
        }
        .dark .nex-comment-action {
            border-color: #3d444d;
            background: rgba(110, 118, 129, 0.20);
            color: #c9d1d9;
        }
        .dark .nex-comment-action:hover,
        .dark .nex-comment-action:focus-visible {
            border-color: #3d444d;
            background: rgba(110, 118, 129, 0.22);
            color: #e6edf3;
        }
        .nex-comment-action-icon {
            width: 12px;
            height: 12px;
            fill: none;
            stroke: currentColor;
            stroke-linecap: round;
            stroke-linejoin: round;
            stroke-width: 1.45;
        }
        .nex-comment-card p {
            margin: 0;
            white-space: pre-wrap;
        }
        .nex-comment-card-malformed {
            border-color: #cf222e;
            background: rgba(207, 34, 46, 0.08);
        }
        @media (max-width: 320px) {
            .nex-review-layout.nex-has-comment-rail {
                grid-template-columns: minmax(0, 1fr);
            }
            .\(MarkdownDOMClass.commentRail) {
                position: static;
                max-height: none;
                min-height: 0;
                overflow: visible;
                margin-top: 24px;
                padding-top: 12px;
                padding-left: 0;
                border-left: none;
                border-top: 1px solid #d1d9e0;
            }
            .\(MarkdownDOMClass.commentRail).nex-comment-rail-positioned .nex-comment-card {
                position: relative;
                left: auto;
                right: auto;
                top: auto !important;
            }
            .dark .\(MarkdownDOMClass.commentRail) {
                border-top-color: #3d444d;
            }
        }
        """
    }
}
