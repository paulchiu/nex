import Foundation

enum MarkdownSourceMutationError: Error, Equatable {
    case unknownBlock(String)
    case unknownTask(String)
    case unknownComment(String)
    case invalidTaskMarker(String)
    case malformedComment(String)
}

struct MarkdownTaskToggleResult {
    var markdown: String
    var previousChecked: Bool
}

enum MarkdownSourceMutations {
    static func insertComment(
        in markdown: String,
        blockID: String,
        selectedText: String,
        anchorStrategy: MarkdownAnchorStrategy,
        commentText: String,
        createdAt: Date = Date()
    ) throws -> String {
        let context = MarkdownRenderPipeline.makeContext(markdown)
        guard let block = context.sourceBlocks.first(where: { $0.id == blockID }) else {
            throw MarkdownSourceMutationError.unknownBlock(blockID)
        }

        let lineEnding = MarkdownSourceMap.dominantLineEnding(in: markdown)
        let comment = MarkdownComment(
            id: makeCommentID(createdAt: createdAt),
            createdAt: createdAt,
            anchorStrategy: anchorStrategy,
            anchorText: selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
            comment: commentText.trimmingCharacters(in: .whitespacesAndNewlines),
            markerRange: markdown.startIndex ..< markdown.startIndex
        )
        let blockText = MarkdownCommentParser.serialize(comment, lineEnding: lineEnding)
        let insertion = block.insertionIndex
        let prefix = markdown[..<insertion]
        let suffix = markdown[insertion...]
        let leading = prefix.hasSuffix(lineEnding) ? lineEnding : lineEnding + lineEnding
        let trailing: String = if suffix.isEmpty {
            markdown.hasSuffix(lineEnding) ? lineEnding : ""
        } else if suffix.hasPrefix(lineEnding) {
            lineEnding
        } else {
            lineEnding + lineEnding
        }
        return String(prefix) + leading + blockText + trailing + String(suffix)
    }

    static func toggleTaskCheckbox(
        in markdown: String,
        taskID: String,
        checked: Bool
    ) throws -> MarkdownTaskToggleResult {
        let context = MarkdownRenderPipeline.makeContext(markdown)
        guard let marker = context.taskMarkers.first(where: { $0.id == taskID }) else {
            throw MarkdownSourceMutationError.unknownTask(taskID)
        }
        let current = String(markdown[marker.markerRange])
        guard current == "[ ]" || current == "[x]" || current == "[X]" else {
            throw MarkdownSourceMutationError.invalidTaskMarker(taskID)
        }

        var updated = markdown
        updated.replaceSubrange(marker.markerRange, with: checked ? "[x]" : "[ ]")
        return MarkdownTaskToggleResult(markdown: updated, previousChecked: marker.checked)
    }

    static func updateComment(
        in markdown: String,
        commentID: String,
        commentText: String
    ) throws -> String {
        let context = MarkdownRenderPipeline.makeContext(markdown)
        guard var comment = context.comments.first(where: { $0.id == commentID }) else {
            throw MarkdownSourceMutationError.unknownComment(commentID)
        }
        guard !comment.isMalformed else {
            throw MarkdownSourceMutationError.malformedComment(commentID)
        }

        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MarkdownSourceMutationError.malformedComment(commentID)
        }
        comment.comment = trimmed
        let serialized = MarkdownCommentParser.serialize(
            comment,
            lineEnding: MarkdownSourceMap.dominantLineEnding(in: markdown)
        )

        var updated = markdown
        updated.replaceSubrange(comment.markerRange, with: serialized)
        return updated
    }

    static func deleteComment(
        in markdown: String,
        commentID: String
    ) throws -> String {
        let context = MarkdownRenderPipeline.makeContext(markdown)
        guard let comment = context.comments.first(where: { $0.id == commentID }) else {
            throw MarkdownSourceMutationError.unknownComment(commentID)
        }

        var updated = markdown
        updated.replaceSubrange(comment.markerRange, with: "")
        return updated
    }

    private static func makeCommentID(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: createdAt)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "nex-\(stamp)-\(suffix)"
    }
}
