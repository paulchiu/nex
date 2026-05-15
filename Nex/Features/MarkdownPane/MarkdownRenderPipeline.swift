import Foundation
import Markdown

enum MarkdownRenderPipeline {
    static func makeContext(_ markdown: String) -> MarkdownRenderContext {
        let body = MarkdownSourceMap.frontMatterBody(in: markdown)
        let scan = MarkdownCommentParser.scan(in: markdown, bodyRange: body.bodyRange)
        let sourceMap = MarkdownSourceMap(
            source: markdown,
            bodyRange: body.bodyRange,
            bodyStartLine: body.bodyStartLine
        )
        let document = Document(parsing: scan.cleanedMarkdown)
        let taskMarkers = MarkdownTaskMarkerBuilder.taskMarkers(
            document: document,
            sourceMap: sourceMap
        )
        let sourceBlocks = MarkdownSourceBlockCollector.collect(
            document: document,
            sourceMap: sourceMap
        )
        let placement = placeComments(scan.comments, on: sourceBlocks)

        return MarkdownRenderContext(
            comments: scan.comments,
            taskMarkers: taskMarkers,
            sourceBlocks: sourceBlocks,
            cleanedMarkdown: scan.cleanedMarkdown,
            sourceMap: sourceMap,
            bodyOffset: sourceMap.bodyOffset,
            commentsByBlockID: placement.commentsByBlockID,
            commentBlockIDs: placement.commentBlockIDs
        )
    }

    static func frontMatter(in markdown: String) -> String? {
        MarkdownSourceMap.frontMatterBody(in: markdown).yaml
    }

    private static func placeComments(
        _ comments: [MarkdownComment],
        on blocks: [MarkdownSourceBlock]
    ) -> (
        commentsByBlockID: [String: [MarkdownComment]],
        commentBlockIDs: [String: String]
    ) {
        guard !blocks.isEmpty else { return ([:], [:]) }

        var commentsByBlockID: [String: [MarkdownComment]] = [:]
        var commentBlockIDs: [String: String] = [:]
        for comment in comments.sorted(by: { $0.markerRange.lowerBound < $1.markerRange.lowerBound }) {
            let block = blocks
                .filter { $0.insertionIndex <= comment.markerRange.lowerBound }
                .last ?? blocks[0]
            commentsByBlockID[block.id, default: []].append(comment)
            commentBlockIDs[comment.id] = block.id
        }
        return (commentsByBlockID, commentBlockIDs)
    }
}

private struct MarkdownSourceBlockCollector: MarkupVisitor {
    typealias Result = Void

    private let sourceMap: MarkdownSourceMap
    private var blocks: [MarkdownSourceBlock] = []

    init(sourceMap: MarkdownSourceMap) {
        self.sourceMap = sourceMap
    }

    static func collect(
        document: Document,
        sourceMap: MarkdownSourceMap
    ) -> [MarkdownSourceBlock] {
        var collector = MarkdownSourceBlockCollector(sourceMap: sourceMap)
        collector.visit(document)
        return collector.blocks
    }

    mutating func defaultVisit(_ markup: any Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        record(heading)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        record(paragraph)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        record(codeBlock)
    }

    mutating func visitListItem(_ item: ListItem) {
        record(item)
        for child in item.children {
            visit(child)
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        record(blockQuote)
        for child in blockQuote.children {
            visit(child)
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        record(thematicBreak)
    }

    mutating func visitTable(_ table: Table) {
        record(table)
        for child in table.children {
            visit(child)
        }
    }

    mutating func visitTableCell(_ cell: Table.Cell) {
        record(cell)
        for child in cell.children {
            visit(child)
        }
    }

    private mutating func record(_ markup: any Markup) {
        let ordinal = blocks.count + 1
        let range = markup.range.flatMap { sourceMap.range(for: $0) }
        blocks.append(MarkdownSourceBlock(
            id: "block-\(ordinal)",
            ordinal: ordinal,
            sourceRange: range,
            insertionIndex: range?.upperBound ?? sourceMap.bodyRange.upperBound,
            renderedText: ""
        ))
    }
}
