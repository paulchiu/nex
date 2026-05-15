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

enum MarkdownAnchorStrategy: String {
    case exactSelection = "exact-selection"
    case nearestBlock = "nearest-block"
}

struct MarkdownComment {
    var id: String
    var createdAt: Date
    var anchorStrategy: MarkdownAnchorStrategy
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
    var renderedText: String
}

struct MarkdownBodyOffset {
    var bodyStartIndex: String.Index
    var bodyStartLine: Int
    var cleanedLineToOriginalLine: [Int: Int]
}

struct MarkdownRenderContext {
    var comments: [MarkdownComment]
    var taskMarkers: [MarkdownTaskMarker]
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
        anchorStrategy: MarkdownAnchorStrategy,
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
                  let rawStrategy = payload["anchorStrategy"] as? String,
                  let strategy = MarkdownAnchorStrategy(rawValue: rawStrategy),
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
                anchorStrategy: strategy,
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

            if !inFence, leadingMarkdownIndent(line.text) < 4, trimmed == "<!-- nex-comment" {
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
        let createdAt = isoFormatter().string(from: comment.createdAt)
        let anchor = serializeBlockScalar(escapeField(comment.anchorText), lineEnding: lineEnding)
        let note = serializeBlockScalar(escapeField(comment.comment), lineEnding: lineEnding)
        return [
            "<!-- nex-comment",
            "id: \"\(escapeQuoted(comment.id))\"",
            "createdAt: \"\(escapeQuoted(createdAt))\"",
            "anchorStrategy: \"\(comment.anchorStrategy.rawValue)\"",
            "anchorText: |-",
            anchor,
            "comment: |-",
            note,
            "-->"
        ].joined(separator: lineEnding)
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
        let rawLines = MarkdownSourceLine.lines(in: source, range: range).map(\.text)
        guard rawLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "<!-- nex-comment",
              rawLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "-->"
        else { return nil }

        var values: [String: String] = [:]
        var index = 1
        while index < rawLines.count - 1 {
            let line = rawLines[index]
            if line.hasPrefix("anchorText: |-") || line.hasPrefix("comment: |-") {
                let key = line.hasPrefix("anchorText: |-") ? "anchorText" : "comment"
                index += 1
                var collected: [String] = []
                while index < rawLines.count - 1 {
                    let candidate = rawLines[index]
                    if isTopLevelField(candidate) { break }
                    if candidate.hasPrefix("  ") {
                        collected.append(String(candidate.dropFirst(2)))
                    } else if candidate.isEmpty {
                        collected.append("")
                    } else {
                        break
                    }
                    index += 1
                }
                values[key] = unescapeField(collected.joined(separator: "\n"))
                continue
            }

            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let valueStart = line.index(after: colon)
                let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
                values[key] = unquote(value)
            }
            index += 1
        }

        guard let id = values["id"],
              let createdAtRaw = values["createdAt"],
              let createdAt = isoFormatter().date(from: createdAtRaw),
              let rawStrategy = values["anchorStrategy"],
              let strategy = MarkdownAnchorStrategy(rawValue: rawStrategy),
              let anchorText = values["anchorText"],
              let comment = values["comment"]
        else { return nil }

        return MarkdownComment(
            id: id,
            createdAt: createdAt,
            anchorStrategy: strategy,
            anchorText: anchorText,
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
            createdAt: Date(timeIntervalSince1970: 0),
            anchorStrategy: .nearestBlock,
            anchorText: "",
            comment: "Malformed Nex comment",
            markerRange: range,
            isMalformed: true
        )
    }

    private static func serializeBlockScalar(_ text: String, lineEnding: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.isEmpty {
            return "  "
        }
        return lines.map { "  \($0)" }.joined(separator: lineEnding)
    }

    private static func escapeQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unquote(_ value: String) -> String {
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
            return value
        }
        let inner = value.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func isTopLevelField(_ line: String) -> Bool {
        line.hasPrefix("id:")
            || line.hasPrefix("createdAt:")
            || line.hasPrefix("anchorStrategy:")
            || line.hasPrefix("anchorText:")
            || line.hasPrefix("comment:")
            || line.trimmingCharacters(in: .whitespacesAndNewlines) == "-->"
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
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
