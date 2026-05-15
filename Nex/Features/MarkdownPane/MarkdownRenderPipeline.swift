import CryptoKit
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
        let comments = deriveRuntimeCommentMetadata(scan.comments, on: sourceBlocks)
        let placement = placeComments(comments, on: sourceBlocks)

        return MarkdownRenderContext(
            comments: comments,
            taskMarkers: taskMarkers,
            taskMarkersByItemRange: taskMarkers.reduce(into: [:]) { result, marker in
                result[marker.itemRange] = marker
            },
            sourceBlocks: sourceBlocks,
            cleanedMarkdown: scan.cleanedMarkdown,
            document: document,
            sourceMap: sourceMap,
            bodyOffset: sourceMap.bodyOffset,
            commentsByBlockID: placement.commentsByBlockID,
            commentBlockIDs: placement.commentBlockIDs
        )
    }

    static func frontMatter(in markdown: String) -> String? {
        MarkdownSourceMap.frontMatterBody(in: markdown).yaml
    }

    private static func deriveRuntimeCommentMetadata(
        _ comments: [MarkdownComment],
        on blocks: [MarkdownSourceBlock]
    ) -> [MarkdownComment] {
        var duplicateCounts: [String: Int] = [:]
        return comments.map { comment in
            guard !comment.isMalformed else { return comment }
            let block = block(for: comment, in: blocks)
            let blockOrdinal = block?.ordinal ?? 0
            let base = "\(blockOrdinal)\u{01}\(comment.anchorText)\u{01}\(comment.comment)"
            let duplicateIndex = duplicateCounts[base, default: 0]
            duplicateCounts[base] = duplicateIndex + 1
            let hashInput = duplicateIndex == 0 ? base : "\(base)\u{01}\(duplicateIndex + 1)"

            var resolved = comment
            resolved.id = "c-\(sha256Prefix(hashInput))"
            return resolved
        }
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
            let block = block(for: comment, in: blocks) ?? blocks[0]
            commentsByBlockID[block.id, default: []].append(comment)
            commentBlockIDs[comment.id] = block.id
        }
        return (commentsByBlockID, commentBlockIDs)
    }

    private static func block(
        for comment: MarkdownComment,
        in blocks: [MarkdownSourceBlock]
    ) -> MarkdownSourceBlock? {
        guard !blocks.isEmpty else { return nil }
        return blocks
            .filter { $0.insertionIndex <= comment.markerRange.lowerBound }
            .last ?? blocks[0]
    }

    private static func sha256Prefix(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
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
            insertionIndex: range?.upperBound ?? sourceMap.bodyRange.upperBound
        ))
    }
}
