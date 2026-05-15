import Foundation
import Markdown

enum MarkdownDOMClass {
    static let commentBlock = "nex-comment-block"
    static let commentBlockActive = "nex-comment-block-active"
    static let commentHighlight = "nex-comment-highlight"
    static let commentHighlightActive = "nex-comment-highlight-active"
    static let commentRail = "nex-comment-rail"
    static let commentCardActive = "nex-comment-card-active"
    static let findMatch = "nex-find-match"
}

struct MarkdownComment {
    var id: String
    var anchorText: String
    var comment: String
    var markerRange: Range<String.Index>
    var isMalformed: Bool = false
}

struct MarkdownTaskMarker {
    var id: String
    var checked: Bool
    var markerRange: Range<String.Index>
    var sourceLine: Int
    var itemRange: Range<String.Index>
}

struct MarkdownSourceBlock {
    var id: String
    var ordinal: Int
    var sourceRange: Range<String.Index>?
    var insertionIndex: String.Index
}

struct MarkdownBodyOffset {
    var bodyStartIndex: String.Index
    var bodyStartLine: Int
    var cleanedLineToOriginalLine: [Int: Int]
}

struct MarkdownRenderContext {
    var comments: [MarkdownComment]
    var taskMarkers: [MarkdownTaskMarker]
    var taskMarkersByItemRange: [Range<String.Index>: MarkdownTaskMarker]
    var sourceBlocks: [MarkdownSourceBlock]
    var cleanedMarkdown: String
    var document: Document
    var sourceMap: MarkdownSourceMap
    var bodyOffset: MarkdownBodyOffset
    var commentsByBlockID: [String: [MarkdownComment]]
    var commentBlockIDs: [String: String]
}

enum MarkdownReviewPayload {
    case addComment(
        selectedText: String,
        blockID: String,
        comment: String
    )
    case toggleTask(taskID: String, checked: Bool)
    case updateComment(commentID: String, comment: String)
    case deleteComment(commentID: String)

    static func parse(_ body: Any) -> MarkdownReviewPayload? {
        guard let payload = body as? [String: Any],
              let type = payload["type"] as? String
        else { return nil }

        switch type {
        case "addComment":
            guard let selectedText = payload["selectedText"] as? String,
                  let blockID = payload["blockID"] as? String,
                  let comment = payload["comment"] as? String
            else { return nil }
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !blockID.isEmpty,
                  !trimmedComment.isEmpty
            else { return nil }
            return .addComment(
                selectedText: selectedText,
                blockID: blockID,
                comment: trimmedComment
            )

        case "toggleTask":
            guard let taskID = payload["taskID"] as? String,
                  let checked = payload["checked"] as? Bool,
                  !taskID.isEmpty
            else { return nil }
            return .toggleTask(taskID: taskID, checked: checked)

        case "updateComment":
            guard let commentID = payload["commentID"] as? String,
                  let comment = payload["comment"] as? String,
                  !commentID.isEmpty
            else { return nil }
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedComment.isEmpty else { return nil }
            return .updateComment(commentID: commentID, comment: trimmedComment)

        case "deleteComment":
            guard let commentID = payload["commentID"] as? String,
                  !commentID.isEmpty
            else { return nil }
            return .deleteComment(commentID: commentID)

        default:
            return nil
        }
    }
}

struct MarkdownCommentScan {
    var comments: [MarkdownComment]
    var cleanedMarkdown: String
    var commentRanges: [Range<String.Index>]
}

enum MarkdownCommentParser {
    static func scan(in source: String, bodyRange: Range<String.Index>) -> MarkdownCommentScan {
        let lines = MarkdownSourceLine.lines(in: source, range: bodyRange)
        var comments: [MarkdownComment] = []
        var ranges: [Range<String.Index>] = []
        var cleaned = ""
        var index = 0
        var inFence = false

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if isFenceLine(line.text) {
                inFence.toggle()
            }

            if !inFence, leadingMarkdownIndent(line.text) < 4, isCandidateOpener(trimmed) {
                let start = line.fullRange.lowerBound
                var end = line.fullRange.upperBound
                var commentLineCount = 1
                var cursor = index + 1
                var foundEnd = false

                while cursor < lines.count {
                    let candidate = lines[cursor]
                    end = candidate.fullRange.upperBound
                    commentLineCount += 1
                    if candidate.text.trimmingCharacters(in: .whitespacesAndNewlines) == "-->" {
                        foundEnd = true
                        break
                    }
                    cursor += 1
                }

                if !foundEnd {
                    let openerRange = line.fullRange
                    ranges.append(openerRange)
                    comments.append(malformedComment(range: openerRange, ordinal: comments.count + 1))
                    cleaned += line.lineEnding
                    index += 1
                    continue
                }

                let range = start ..< end
                ranges.append(range)
                for hiddenLine in lines[index ..< index + commentLineCount] {
                    cleaned += hiddenLine.lineEnding
                }
                if let comment = parseCommentBlock(in: source, range: range) {
                    comments.append(comment)
                } else {
                    comments.append(malformedComment(range: range, ordinal: comments.count + 1))
                }
                index += commentLineCount
                continue
            }

            cleaned += String(source[line.fullRange])
            index += 1
        }

        return MarkdownCommentScan(
            comments: comments,
            cleanedMarkdown: cleaned,
            commentRanges: ranges
        )
    }

    static func serialize(_ comment: MarkdownComment, lineEnding: String) -> String {
        let body = comment.comment
            .components(separatedBy: "\n")
            .map(escapeField)
        return (["<!--nx \"\(escapeAnchor(comment.anchorText))\""] + body + ["-->"])
            .joined(separator: lineEnding)
    }

    static func escapeField(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "--", with: "-\\u002D")
    }

    static func unescapeField(_ text: String) -> String {
        text.replacingOccurrences(of: "-\\u002D", with: "--")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseCommentBlock(
        in source: String,
        range: Range<String.Index>
    ) -> MarkdownComment? {
        let lines = MarkdownSourceLine.lines(in: source, range: range)
        let rawLines = lines.map(\.text)
        guard let first = rawLines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let anchor = parseOpenerAnchor(first),
              rawLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "-->"
        else { return nil }

        let lineEnding = MarkdownSourceMap.dominantLineEnding(in: source)
        let comment = unescapeField(rawLines.dropFirst().dropLast().joined(separator: lineEnding))

        return MarkdownComment(
            id: "",
            anchorText: anchor,
            comment: comment,
            markerRange: range
        )
    }

    private static func malformedComment(
        range: Range<String.Index>,
        ordinal: Int
    ) -> MarkdownComment {
        MarkdownComment(
            id: "malformed-\(ordinal)",
            anchorText: "",
            comment: "Malformed Nex comment",
            markerRange: range,
            isMalformed: true
        )
    }

    private static func escapeAnchor(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func parseOpenerAnchor(_ line: String) -> String? {
        let prefix = "<!--nx \""
        guard line.hasPrefix(prefix), line.hasSuffix("\"") else { return nil }
        let inner = line.dropFirst(prefix.count).dropLast()
        var result = ""
        var index = inner.startIndex
        while index < inner.endIndex {
            let character = inner[index]
            if character != "\\" {
                result.append(character)
                index = inner.index(after: index)
                continue
            }

            let next = inner.index(after: index)
            guard next < inner.endIndex else { return nil }
            switch inner[next] {
            case "\\":
                result.append("\\")
            case "\"":
                result.append("\"")
            case "n":
                result.append("\n")
            default:
                return nil
            }
            index = inner.index(after: next)
        }
        return result
    }

    private static func isCandidateOpener(_ line: String) -> Bool {
        line.hasPrefix("<!--nx \"")
    }

    private static func isFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return leadingMarkdownIndent(line) < 4 &&
            (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~"))
    }

    private static func leadingMarkdownIndent(_ line: String) -> Int {
        var indent = 0
        for character in line {
            if character == " " {
                indent += 1
            } else if character == "\t" {
                indent += 4
            } else {
                break
            }
        }
        return indent
    }
}
