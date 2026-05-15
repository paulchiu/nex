import Foundation
import Markdown

struct MarkdownSourceLine {
    var number: Int
    var text: String
    var contentRange: Range<String.Index>
    var fullRange: Range<String.Index>
    var lineEnding: String

    static func lines(
        in source: String,
        range: Range<String.Index>? = nil
    ) -> [MarkdownSourceLine] {
        let bounds = range ?? source.startIndex ..< source.endIndex
        guard bounds.lowerBound < bounds.upperBound else { return [] }

        var result: [MarkdownSourceLine] = []
        var cursor = bounds.lowerBound
        var lineNumber = lineNumber(at: cursor, in: source)

        while cursor < bounds.upperBound {
            var lineEnd = cursor
            while lineEnd < bounds.upperBound, !isLineEnding(source[lineEnd]) {
                lineEnd = source.index(after: lineEnd)
            }

            let endingStart = lineEnd
            var next = lineEnd
            var ending = ""
            if next < bounds.upperBound {
                ending = String(source[next])
                next = source.index(after: next)
            }

            result.append(MarkdownSourceLine(
                number: lineNumber,
                text: String(source[cursor ..< lineEnd]),
                contentRange: cursor ..< lineEnd,
                fullRange: cursor ..< next,
                lineEnding: ending
            ))

            if endingStart == bounds.upperBound { break }
            cursor = next
            lineNumber += 1
        }

        return result
    }

    private static func isLineEnding(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n" || character == "\r"
    }

    private static func lineNumber(at index: String.Index, in source: String) -> Int {
        var number = 1
        var cursor = source.startIndex
        while cursor < index {
            if isLineEnding(source[cursor]) {
                number += 1
            }
            cursor = source.index(after: cursor)
        }
        return number
    }
}

struct MarkdownFrontMatterBody {
    var yaml: String?
    var bodyRange: Range<String.Index>
    var bodyStartLine: Int
}

struct MarkdownSourceMap {
    let source: String
    let bodyRange: Range<String.Index>
    let bodyOffset: MarkdownBodyOffset
    private let lineStarts: [String.Index]

    init(source: String, bodyRange: Range<String.Index>, bodyStartLine: Int) {
        self.source = source
        self.bodyRange = bodyRange
        bodyOffset = MarkdownBodyOffset(
            bodyStartIndex: bodyRange.lowerBound,
            bodyStartLine: bodyStartLine,
            cleanedLineToOriginalLine: [:]
        )
        lineStarts = Self.buildLineStarts(in: source)
    }

    func range(for sourceRange: SourceRange) -> Range<String.Index>? {
        let lowerLine = bodyOffset.bodyStartLine + sourceRange.lowerBound.line - 1
        let upperLine = bodyOffset.bodyStartLine + sourceRange.upperBound.line - 1
        guard let lower = index(line: lowerLine, column: sourceRange.lowerBound.column),
              let upper = index(line: upperLine, column: sourceRange.upperBound.column),
              lower <= upper
        else { return nil }
        return lower ..< upper
    }

    func index(line: Int, column: Int) -> String.Index? {
        guard line > 0, column > 0 else { return nil }
        if line > lineStarts.count {
            return source.endIndex
        }
        let lineStart = lineStarts[line - 1]
        let byteOffset = column - 1
        guard let utf8Start = lineStart.samePosition(in: source.utf8) else {
            return nil
        }
        guard let utf8Target = source.utf8.index(
            utf8Start,
            offsetBy: byteOffset,
            limitedBy: source.utf8.endIndex
        ) else {
            return source.endIndex
        }
        var cursor = utf8Target
        while cursor <= source.utf8.endIndex {
            if let stringIndex = String.Index(cursor, within: source) {
                return stringIndex
            }
            if cursor == source.utf8.endIndex { break }
            cursor = source.utf8.index(after: cursor)
        }
        return nil
    }

    static func frontMatterBody(in markdown: String) -> MarkdownFrontMatterBody {
        let lines = MarkdownSourceLine.lines(in: markdown)
        guard let first = lines.first else {
            return MarkdownFrontMatterBody(
                yaml: nil,
                bodyRange: markdown.startIndex ..< markdown.endIndex,
                bodyStartLine: 1
            )
        }

        let firstText = first.text.hasPrefix("\u{FEFF}")
            ? String(first.text.dropFirst())
            : first.text
        guard isFence(firstText, marker: "---") else {
            return MarkdownFrontMatterBody(
                yaml: nil,
                bodyRange: markdown.startIndex ..< markdown.endIndex,
                bodyStartLine: 1
            )
        }

        var bytesScanned = 0
        for line in lines.dropFirst() {
            if isFence(line.text, marker: "---") || isFence(line.text, marker: "...") {
                let yamlStart = first.fullRange.upperBound
                let yamlEnd = line.fullRange.lowerBound
                let bodyStart = line.fullRange.upperBound
                let yaml = String(markdown[yamlStart ..< yamlEnd]).trimmingTrailingMarkdownNewline()
                return MarkdownFrontMatterBody(
                    yaml: yaml,
                    bodyRange: bodyStart ..< markdown.endIndex,
                    bodyStartLine: line.number + 1
                )
            }
            bytesScanned += line.text.utf8.count + line.lineEnding.utf8.count
            if bytesScanned > 64 * 1024 {
                return MarkdownFrontMatterBody(
                    yaml: nil,
                    bodyRange: markdown.startIndex ..< markdown.endIndex,
                    bodyStartLine: 1
                )
            }
        }

        return MarkdownFrontMatterBody(
            yaml: nil,
            bodyRange: markdown.startIndex ..< markdown.endIndex,
            bodyStartLine: 1
        )
    }

    static func dominantLineEnding(in source: String) -> String {
        let crlf = source.components(separatedBy: "\r\n").count - 1
        var lf = 0
        var cr = 0
        for character in source {
            if character == "\r\n" {
                continue
            } else if character == "\n" {
                lf += 1
            } else if character == "\r" {
                cr += 1
            }
        }
        if crlf >= lf, crlf >= cr, crlf > 0 {
            return "\r\n"
        }
        if cr > lf, cr > 0 {
            return "\r"
        }
        return "\n"
    }

    private static func buildLineStarts(in source: String) -> [String.Index] {
        var starts = [source.startIndex]
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let character = source[cursor]
            let next = source.index(after: cursor)
            if character == "\n" || character == "\r\n" || character == "\r" {
                starts.append(next)
            }
            cursor = next
        }
        return starts
    }

    private static func isFence(_ line: String, marker: String) -> Bool {
        guard line.hasPrefix(marker) else { return false }
        let rest = line.dropFirst(marker.count)
        return rest.allSatisfy { $0 == " " || $0 == "\t" }
    }
}

enum MarkdownTaskMarkerBuilder {
    static func taskMarkers(
        in source: String,
        bodyRange: Range<String.Index>,
        excluding commentRanges: [Range<String.Index>] = []
    ) -> [MarkdownTaskMarker] {
        let lines = MarkdownSourceLine.lines(in: source, range: bodyRange)
        var markers: [MarkdownTaskMarker] = []
        var inFence = false
        var inCommentRange = false

        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if commentRanges.contains(where: { $0.overlaps(line.fullRange) }) {
                inCommentRange = true
            } else {
                inCommentRange = false
            }
            if !inCommentRange, isFenceLine(line.text) {
                inFence.toggle()
            }
            guard !inFence, !inCommentRange, !trimmed.hasPrefix(">"),
                  let markerRange = taskMarkerRange(in: source, line: line)
            else { continue }

            let marker = String(source[markerRange])
            let checked = marker == "[x]" || marker == "[X]"
            markers.append(MarkdownTaskMarker(
                id: "task-\(markers.count + 1)",
                checked: checked,
                markerRange: markerRange,
                sourceLine: line.number
            ))
        }

        return markers
    }

    private static func taskMarkerRange(
        in source: String,
        line: MarkdownSourceLine
    ) -> Range<String.Index>? {
        var cursor = line.contentRange.lowerBound
        while cursor < line.contentRange.upperBound,
              source[cursor] == " " || source[cursor] == "\t" {
            cursor = source.index(after: cursor)
        }
        guard cursor < line.contentRange.upperBound else { return nil }

        if source[cursor].isNumber {
            var digitEnd = cursor
            while digitEnd < line.contentRange.upperBound, source[digitEnd].isNumber {
                digitEnd = source.index(after: digitEnd)
            }
            guard digitEnd < line.contentRange.upperBound,
                  source[digitEnd] == "." || source[digitEnd] == ")"
            else { return nil }
            cursor = source.index(after: digitEnd)
        } else if source[cursor] == "-" || source[cursor] == "+" || source[cursor] == "*" {
            cursor = source.index(after: cursor)
        } else {
            return nil
        }

        guard cursor < line.contentRange.upperBound,
              source[cursor] == " " || source[cursor] == "\t"
        else { return nil }
        while cursor < line.contentRange.upperBound,
              source[cursor] == " " || source[cursor] == "\t" {
            cursor = source.index(after: cursor)
        }

        guard let markerEnd = source.index(cursor, offsetBy: 3, limitedBy: line.contentRange.upperBound),
              source[cursor] == "[",
              source[source.index(after: cursor)] == " "
              || source[source.index(after: cursor)] == "x"
              || source[source.index(after: cursor)] == "X",
              source[source.index(cursor, offsetBy: 2)] == "]"
        else { return nil }

        return cursor ..< markerEnd
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

private extension String {
    func trimmingTrailingMarkdownNewline() -> String {
        if let last, last == "\n" || last == "\r\n" || last == "\r" {
            return String(dropLast())
        }
        return self
    }
}
