# Prototype: Markdown comment mode and interactive task checkboxes

**Status:** implementation guidance only
**Created:** 2026-05-15
**Branch:** `codex/markdown-comment-mode-plan`

## Scope

Add two related markdown preview capabilities:

* **Comment mode:** a review layer for rendered markdown preview. Users select rendered text, add a plain-text comment, and Nex writes a portable HTML comment block into the markdown file near the selected source.
* **Interactive task checkboxes:** normal markdown task list items can be clicked in preview mode and Nex writes only the source marker change (`[ ]` to `[x]`, or `[x]`/`[X]` to `[ ]`).

This is not a replacement for edit mode. True tracked edits, threaded discussion, author metadata, resolve state, and non-markdown checkbox/comment state are intentionally out of scope for the prototype.

## Agreed vocabulary

* **Comment mode:** a preview-only mode that enables selection comments.
* **Comment:** plain text attached to a selected rendered range.
* **Anchor:** metadata used to reconnect a comment to the selected source text.
* **Comment marker:** the hidden HTML comment block stored in the markdown source.
* **Comment UI:** visible highlight plus note rail/callout in the rendered preview.
* **Task checkbox:** a real markdown task item using `- [ ]`, `- [x]`, `- [X]`, or ordered-list equivalent syntax.

## User decisions

* Comments are created from the **rendered preview**, not raw editor mode.
* Exact/simple rendered selections should anchor precisely.
* Ambiguous selections should still be allowed and attach to the nearest source block.
* Comments are visible in the viewer as a highlight plus a distinct comment UI. A rail should appear only when the document has comments.
* Comment text is plain text only.
* No author, no resolve state, no threads.
* Comments are portable source content and should travel with the markdown file.
* Comment markers should live near the relevant source, not in front matter or an external database.
* Task checkbox clicks are always active in markdown view mode, independent of comment mode.
* Checkbox writes should be optimistic: update the preview first, write source, then let the file watcher settle.

## Current code map

* `WorkspaceFeature.openMarkdownFile` creates markdown panes with `type: .markdown`, `filePath`, title/label, and parent directory ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/Workspace/WorkspaceFeature.swift#L350)).
* `PaneGridView` switches markdown panes between `MarkdownPaneView`, `MarkdownEditorView`, and external-editor `SurfaceContainerView` ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/PaneGrid/PaneGridView.swift#L159)).
* `MarkdownPaneView` is the preview WKWebView host ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownPaneView.swift#L14)).
* `MarkdownPaneView.Coordinator.loadFile()` reads UTF-8 source and calls `renderAndReload` ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownPaneView.swift#L148)).
* `renderAndReload(content:)` calls `MarkdownRenderer.renderToHTML(...)` and `loadHTMLString`, preserving scroll position ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownPaneView.swift#L178)).
* `startWatching()` reloads on write/extend/rename/delete and handles vim-style saves ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownPaneView.swift#L266)).
* The WK bridge currently only registers `scrollHandler` and `nexFind` ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownPaneView.swift#L37)).
* `MarkdownFindScript` is the existing injected JS pattern to mirror for a comment script ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownFindScript.swift#L3)).
* `MarkdownFindController` routes reducer actions to the markdown WKWebView coordinator ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownFindController.swift#L22)).
* `ContentView` translates markdown find notifications back into workspace actions ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/ContentView.swift#L300)).
* `MarkdownRenderer.renderToHTML` strips front matter, parses with swift-markdown, renders via `MarkdownHTMLRenderer`, and wraps a full HTML document ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift#L220)).
* `MarkdownHTMLRenderer.visitListItem` already emits task-list checkbox inputs, but they are disabled and have no source metadata ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift#L87)).
* `visitHTMLBlock` and `visitInlineHTML` currently pass raw HTML through unchanged, including comments ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift#L132)).
* Task list CSS lives in the renderer stylesheet ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift#L351)).
* Header copy/edit buttons are in `PaneHeaderView`, which is the natural home for a comment-mode toggle ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/PaneGrid/PaneHeaderView.swift#L107), [GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/PaneGrid/PaneHeaderView.swift#L126)).
* `WorkspaceFeature.toggleMarkdownEdit` clears markdown find state when entering edit mode and may launch an external editor ([GitHub](https://github.com/paulchiu/nex/blob/main/Nex/Features/Workspace/WorkspaceFeature.swift#L730)).

## ast-grep research performed

The planning pass used structural search to confirm the relevant Swift surfaces:

```bash
ast-grep run --pattern 'config.userContentController.add($HANDLER, name: $NAME)' \
  --lang swift Nex/Features/MarkdownPane/MarkdownPaneView.swift --json

ast-grep run --pattern 'webView?.evaluateJavaScript($JS)' \
  --lang swift Nex/Features/MarkdownPane/MarkdownPaneView.swift --json

ast-grep run --pattern 'mutating func $NAME($$$PARAMS) -> String { $$$BODY }' \
  --lang swift Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift --json

ast-grep run --pattern 'struct $NAME: View { $$$BODY }' \
  --lang swift Nex/Features/MarkdownPane Nex/Features/PaneGrid NexTests --json
```

Key findings:

* The markdown WK bridge is narrow today: scroll and find only.
* Renderer ownership is centralized in `MarkdownHTMLRenderer.swift`.
* Task-list inputs are already emitted in one place and can be made interactive with source metadata.
* Comment-mode UI can be added without touching socket/CLI/persistence.

## Proposed source format

Store comments as one YAML-ish HTML comment block after the selected source block. Even for an exact rendered-text selection, the source marker is block-adjacent for the prototype; exactness is recovered in the preview by matching `anchorText` inside that rendered block.

```markdown
This is the selected sentence.

<!-- nex-comment
id: "nex-20260515-103122-a83f"
createdAt: "2026-05-15T10:31:22Z"
anchorStrategy: "exact-selection"
anchorText: |-
  This is the selected sentence.
comment: |-
  This needs a stronger decision statement.
-->
```

Fallback nearest-block comments use the same format:

```markdown
<!-- nex-comment
id: "nex-20260515-103500-b44e"
createdAt: "2026-05-15T10:35:00Z"
anchorStrategy: "nearest-block"
anchorText: |-
  selected rendered text that did not map exactly
comment: |-
  This applies to the nearby paragraph.
-->
```

Notes:

* Keep all comment fields plain text.
* Do not store hash fields in the prototype. `anchorHash` and `sourceBlockHash` can return later only with a defined canonicalization and stale-comment behavior.
* Writer output must be blank-line-delimited: one blank line before `<!-- nex-comment`, and the closing `-->` on its own line. This keeps Nex-authored comments block-level and avoids inline HTML ambiguity.
* Recognize only line-isolated Nex comment blocks outside fenced code blocks. A literal `<!-- nex-comment` inside a code fence or inline after paragraph text is not parsed as Nex metadata and must not be stripped from the source model.
* Escape `--` reversibly inside `anchorText` and `comment` before serialization, because `--` is invalid inside HTML comments. Use this ASCII-only field escape:
  * On write, replace `\` with `\\`, then replace every `--` with `-\u002D`.
  * On read, replace `-\u002D` with `--`, then replace `\\` with `\`.
  * Serializer tests must assert the final HTML comment body contains no raw `--` except the closing delimiter.
* Use Yams if convenient, since the app already depends on it. If the parser is too strict for malformed blocks, fail closed: hide the raw Nex comment and render a small "Malformed Nex comment" card rather than exposing source syntax.
* Unknown HTML comments should keep current behavior.

## Recommended architecture

### 1. Source model and mutations

Add source-level helpers under `Nex/Features/MarkdownPane/`:

* `MarkdownComment.swift`
  * `MarkdownComment`
  * `MarkdownAnchorStrategy`
  * `MarkdownCommentParser`
  * comment block serialization
  * comment field escaping/sanitization, including the `--` round-trip escape
* `MarkdownSourceMap.swift`
  * line start index
  * byte/range helpers over the original source bytes
  * front-matter body offset metadata
  * source block identity helpers
  * AST-aligned task marker discovery
* `MarkdownSourceMutations.swift`
  * `insertComment(...)`
  * `toggleTaskCheckbox(...)`

Important constraint: mutation helpers should replace only the exact source region required. Do not reserialize the full markdown document.

For task checkboxes, do not assign IDs from a raw source-line regex. The rendered DOM is driven by swift-markdown's task-list interpretation, and raw regex scanning can count cases that do not render as checkboxes, such as blockquoted task-looking text. Instead:

1. Build task markers by walking the same `Document` / `ListItem.checkbox` nodes that `MarkdownHTMLRenderer.visitListItem` renders.
2. Use each task-list node's source range, when present, to find the exact `[ ]`, `[x]`, or `[X]` marker in the original source after applying the front-matter/comment blanking offset map.
3. Fall back to a fence-aware source scanner only when the AST node range is missing and the next marker can be matched unambiguously to the current rendered task-list visit order.
4. If a rendered checkbox cannot be mapped uniquely to a source marker, render it disabled and omit `data-nex-task-id`; never risk toggling the wrong line.

Each interactive rendered checkbox should get a `data-nex-task-id` that maps back to one `MarkdownTaskMarker`. The click handler should post `taskID` and desired checked state, not raw line text.

### 2. Render context

Introduce a render context object rather than making the renderer infer everything from HTML strings:

```swift
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
}

struct MarkdownTaskMarker {
    var id: String
    var checked: Bool
    var markerRange: Range<String.Index>
    var sourceLine: Int
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
    var bodyOffset: MarkdownBodyOffset
}

enum MarkdownReviewPayload {
    case addComment(selectedText: String, blockID: String, anchorStrategy: MarkdownAnchorStrategy)
    case toggleTask(taskID: String, checked: Bool)
}
```

The public renderer can preserve the current convenience API:

```swift
MarkdownRenderer.renderToHTML(markdown, ...)
```

But internally it should delegate to a small pipeline owned by the renderer work, for example `MarkdownRenderPipeline.swift`. That pipeline owns the public `MarkdownRenderer.renderToHTML(...)` orchestration while `MarkdownHTMLRenderer` stays focused on visiting swift-markdown nodes.

The pipeline should build a source model first:

1. Extract front matter with existing `FrontMatterExtractor`.
2. Scan the body with a Markdown-aware comment scanner that tracks fenced code blocks and recognizes only line-isolated `<!-- nex-comment ... -->` blocks.
3. Parse recognized comment blocks and record their original source ranges.
4. Preserve line numbering by replacing each removed `<!-- nex-comment ... -->` byte range with the same number of newline separators it contained. The goal is same line count, not same byte count.
5. Parse the cleaned body with swift-markdown.
6. Walk swift-markdown blocks to assign stable visit-order `data-nex-block-id` values. Use source ranges when available; otherwise use visit-order IDs and mark the source range as unknown.
7. Walk swift-markdown task-list items to assign task IDs only when the rendered checkbox can be mapped to a `MarkdownTaskMarker`.
8. Emit a comment rail/callout from the parsed comment list.

The front-matter offset matters. Current parsing strips front matter before `Document(parsing: body)`, so any source ranges from swift-markdown are relative to the stripped body. Carry body line/byte offsets explicitly. Treat swift-markdown source ranges as optional: use them when available, but fall back to visit-order source block IDs instead of failing or dropping comments.

### 3. Comment rendering

The prototype should render:

* Highlight around the exact selected text when it can be found inside the anchor block.
* Whole-block highlight when exact text matching fails.
* Comment rail only when at least one comment exists.
* Comment cards as escaped plain text.

MVP anchoring contract:

* Swift inserts the comment marker after the selected block's source, never inside inline markdown syntax.
* The JS payload sends `selectedText` and `blockID`, not rendered-text offsets. Swift does not try to translate DOM character offsets to source byte offsets for the prototype.
* Renderer emits whole-block highlights directly for blocks with comments.
* `MarkdownReviewScript` refines to exact text highlight after load by searching for `anchorText` inside that one rendered block. If it cannot find a unique match, the whole-block highlight remains.
* Find highlights and comment highlights must coexist: update `MarkdownFindScript.shouldSkipNode` to skip `.nex-comment-highlight` and `.nex-comment-rail`, and make the comment script avoid wrapping inside existing `mark.nex-find-match` nodes.

### 4. WKWebView bridge

Add a new script handler next to `scrollHandler` and `nexFind` in `MarkdownPaneView.makeNSView`:

```swift
config.userContentController.add(handler, name: "nexMarkdownReview")
```

Add `MarkdownReviewScript.swift`, mirroring the style of `MarkdownFindScript.swift`.

The script should handle:

* Comment mode on/off.
* Selection capture from `window.getSelection()`.
* Anchor block lookup from the selection range:
  * If the range has a common ancestor inside one `[data-nex-block-id]`, use that block and `anchorStrategy: "exact-selection"`.
  * If the selection spans multiple rendered blocks, use the range start container's nearest `[data-nex-block-id]` and `anchorStrategy: "nearest-block"`.
  * If no block can be found, do not show the add-comment popover.
* Add-comment popover in the DOM.
* Checkbox click listeners.
* Optimistic checkbox updates.
* Failure rollback hook, e.g. `window.__nexMarkdownReview.revertTask(taskID, checked)`.
* Hard reset of any in-flight popover state after an HTML reload. A render caused by font-size changes, file changes, or comment insertion may discard a partially typed comment.

Messages to Swift:

```json
{
  "type": "addComment",
  "selectedText": "...",
  "blockID": "...",
  "anchorStrategy": "exact-selection"
}
```

```json
{
  "type": "toggleTask",
  "taskID": "task-7",
  "checked": true
}
```

The coordinator should:

* Keep `currentContent` as the source of truth.
* Mutate `currentContent` optimistically before writing.
* Preserve the original byte contract on write:
  * detect and preserve UTF-8 BOM when present by reading raw `Data(contentsOf:)` at load time and storing a `hasLeadingBOM` flag; `String(contentsOfFile:encoding:.utf8)` is not enough because it consumes the BOM;
  * preserve the dominant line ending style (`\n` or `\r\n`);
  * preserve whether the file ended with a trailing newline;
  * continue to reject non-UTF-8 files rather than transcoding them silently.
* Write in place for this prototype instead of using an atomic rename. Atomic `String.write(..., atomically: true)` triggers the watcher rename/delete path and creates a 200 ms watcher-down window.
* Serialize writes per coordinator and temporarily ignore duplicate clicks for the same task ID while a write is in flight.
* Re-render immediately after successful comment insertion.
* For checkbox toggles, avoid full reload when possible; optimistic DOM update is enough if `currentContent` has already been updated byte-for-byte with the on-disk write.
* On write failure, ask JS to revert the checkbox or show a small error state.
* In `dismantleNSView`, explicitly call `removeScriptMessageHandler(forName:)` for `scrollHandler`, `nexFind`, and `nexMarkdownReview` before releasing the coordinator's web view reference.

### 5. Header and view state

For the prototype, keep comment-mode state view-local in `PaneGridView`, similar to `diffRefreshTokens`:

```swift
@State private var markdownCommentModes: [UUID: Bool] = [:]
```

Reasons:

* Comment mode is UI mode, not persisted pane identity.
* It does not need socket, database, or CLI behavior.
* It can reset when a pane is recreated without losing document comments.

Add to `PaneHeaderView`:

* `var isCommentMode: Bool = false`
* `var onToggleCommentMode: (() -> Void)?`
* Header button visible only for markdown preview panes.
* Use a symbol such as `text.bubble` or `bubble.left.and.text.bubble.right`.
* Help text: `Comment mode`.

Thread state through `PaneGridView` into `MarkdownPaneView(commentModeEnabled:)`.

When a markdown pane enters edit mode, clear its entry from `markdownCommentModes` so the preview script is not left conceptually active behind the editor.

If future implementation adds a keybinding or command-palette action for comment mode, move the state to `WorkspaceFeature.State` as `markdownCommentModePaneIDs: Set<UUID>`.

## Implementation phases

### Phase 1: Source helpers

Deliver:

* Parse/serialize `nex-comment` HTML comments.
* Strip or blank recognized comment blocks for rendering without touching comment lookalikes inside fenced code blocks.
* Build source line index and source block/task marker maps with explicit front-matter/body offsets.
* Toggle task marker mutation without full document rewrite.
* Insert comment blocks after the selected block source, including exact-selection comments.
* Preserve BOM, line endings, and trailing-newline state during mutations.

Tests:

* Parse valid comment block.
* Malformed comment block is handled safely.
* Unknown HTML comment remains unknown.
* Comment text containing `--` and `-->` round-trips through write -> read -> write.
* Comment block inside a fenced code block is not parsed as a Nex comment.
* A `<!-- nex-comment` string adjacent to paragraph text is not stripped or allowed to eat the paragraph.
* Insert exact-selection comment after the target source block.
* Insert nearest-block comment after nearest block.
* Toggle unchecked, checked lowercase, checked uppercase.
* Preserve indentation, list marker, line endings, BOM, trailing-newline state, and unrelated text.
* Toggle mapping does not count blockquoted task-looking text that swift-markdown does not render as a checkbox.

### Phase 2: Renderer

Deliver:

* `MarkdownRenderer` consumes the source model through `MarkdownRenderPipeline.swift`.
* Recognized Nex comment blocks are hidden as raw syntax.
* Comment cards/rail render only when comments exist.
* Supported block tags get stable `data-nex-block-id`.
* Task checkboxes get `data-nex-task-id` and are no longer disabled only when they have a unique `MarkdownTaskMarker`; unmapped task-looking items stay disabled.
* Checkbox cursor changes from default to pointer.
* Existing front matter rendering still works.
* Existing unknown raw HTML behavior is preserved.
* Comment rail renders inside `#content` with `.nex-comment-rail`, and copy-as-rich-text strips it alongside front matter.

Tests:

* Existing `MarkdownHTMLRendererTests` and `MarkdownCheckboxRenderingTests` still pass, updated only for intentional attribute changes.
* Nex comment block is not present as raw `<!-- nex-comment` in rendered HTML.
* Comment text is escaped.
* Comment rail is absent when there are no comments.
* Comment rail is present when comments exist.
* Task checkbox contains `data-nex-task-id`.
* Blockquoted `[x]` text is not counted as a task marker if it does not render as an interactive checkbox.
* Front matter plus comments keeps correct body behavior.
* Copy-as-rich-text excludes `.nex-comment-rail`.

### Phase 3: WK bridge

Deliver:

* Inject `MarkdownReviewScript`.
* Add `nexMarkdownReview` handler.
* Toggle script mode from `MarkdownPaneView.updateNSView`.
* Capture selection and deterministic anchor block using the range common ancestor or start container fallback.
* Show add-comment DOM popover.
* Post add-comment and toggle-task messages to Swift.
* Mutate source through helpers.
* Re-render after comment insertion.
* Optimistically toggle checkbox and roll back on write failure.
* Remove all WK script message handlers in `dismantleNSView`.
* Make find highlights and comment highlights coexist without `parent.normalize()` destroying comment spans.

Tests:

* Unit-test Swift message parsing if extracted into a small payload type.
* Unit-test task/comment payload validation, including missing `blockID`, unknown `taskID`, and unsupported `anchorStrategy`.
* Add a focused DOM/script test or manual checklist for: find active -> comment highlight applied -> find clears -> comment highlight remains.
* Keep direct browser/UI automation for the final implementation pass rather than overfitting unit tests around WKWebView internals.

### Phase 4: Header integration

Deliver:

* Add comment-mode button to markdown preview header.
* Maintain `markdownCommentModes` in `PaneGridView`.
* Pass `commentModeEnabled` to `MarkdownPaneView`.
* Clear comment mode when switching to edit mode or closing/removing a pane.
* Do not show the button for shell, scratchpad, diff, or markdown edit mode.

Tests:

* Prefer reducer-bound tests only if comment mode moves into `WorkspaceFeature.State`.
* Otherwise rely on focused SwiftUI/manual verification because the state is view-local, as with `diffRefreshTokens`.

### Phase 5: Verification

Run:

```bash
xcodebuild -scheme Nex -destination 'platform=macOS' -skipMacroValidation \
  -only-testing:NexTests/MarkdownHTMLRendererTests test

xcodebuild -scheme Nex -destination 'platform=macOS' -skipMacroValidation \
  -only-testing:NexTests/MarkdownCheckboxRenderingTests test

xcodebuild -scheme Nex -destination 'platform=macOS' -skipMacroValidation \
  -only-testing:NexTests/WorkspaceFeatureTests test

xcodebuild -scheme Nex -destination 'platform=macOS' -skipMacroValidation test
```

For manual QA:

1. Open a markdown file with existing task checkboxes.
2. Click unchecked and checked tasks in preview mode.
3. Confirm only the marker changes in source.
4. Repeat with a file that uses `\r\n`, a UTF-8 BOM, and no trailing newline; confirm those bytes are preserved.
5. Open the same file in two markdown panes, toggle a checkbox in one pane, and confirm the other pane reloads to the same checked state.
6. Toggle comment mode.
7. Select text inside one paragraph and add a comment.
8. Confirm a block-adjacent `nex-comment` block is inserted near the source.
9. Confirm the raw comment syntax is hidden in preview.
10. Confirm the comment rail appears.
11. Select text spanning multiple rendered blocks.
12. Confirm Nex attaches a nearest-block comment rather than failing.
13. Use find-in-page before and after comment highlighting; confirm clearing find marks does not remove comment highlights.

## Subagent implementation plan

The following split is designed to avoid overlapping write sets. Do not run A-D fully in parallel until the shared type contract below is merged or copied verbatim into each worker brief. Workers should use `ast-grep` for structural code checks when line-oriented `rg` is too weak, especially around SwiftUI view initializers, `WKScriptMessageHandler` registrations, and `MarkdownHTMLRenderer` visitor methods.

Shared type contract before parallel work:

* `MarkdownAnchorStrategy`
* `MarkdownComment`
* `MarkdownTaskMarker`
* `MarkdownSourceBlock`
* `MarkdownBodyOffset`
* `MarkdownRenderContext`
* `MarkdownReviewPayload`
* Shared DOM/CSS class constants used across renderer, review script, find script, and copy stripping:
  * `nex-comment-highlight`
  * `nex-comment-rail`
  * `nex-find-match`

Worker A should land this contract first, even if parser/mutation behavior is still incomplete. Other workers must consume these exact shapes rather than inventing temporary alternatives.

### Worker A: Source model and mutations

Owns:

* `Nex/Features/MarkdownPane/MarkdownComment.swift`
* `Nex/Features/MarkdownPane/MarkdownSourceMap.swift`
* `Nex/Features/MarkdownPane/MarkdownSourceMutations.swift`
* `NexTests/MarkdownCommentTests.swift`
* `NexTests/MarkdownSourceMutationTests.swift`

Do not edit:

* `MarkdownPaneView.swift`
* `PaneGridView.swift`
* `PaneHeaderView.swift`

Output contract:

* Shared public types listed above.
* Public helpers for comment parse/serialize, including the reversible `--` escape.
* Public helpers for AST-aligned task marker discovery and mutation.
* Public helper for comment insertion from a block/selection payload.
* Tests covering fenced code, inline-adjacent comment lookalikes, BOM/line-ending/trailing-newline preservation, and blockquoted task-looking text.

### Worker B: Renderer and HTML/CSS

Owns:

* `Nex/Features/MarkdownPane/MarkdownRenderPipeline.swift`
* `Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift`
* `NexTests/MarkdownHTMLRendererTests.swift`
* `NexTests/MarkdownCheckboxRenderingTests.swift`

Depends on Worker A public types. Do not define alternate protocol or initializer shapes; wait for the types-only contract if needed.

Do not edit:

* `MarkdownPaneView.swift`
* pane header/grid files

Output contract:

* `MarkdownRenderPipeline.swift` owns `MarkdownRenderer.renderToHTML(...)` orchestration: front matter extraction, comment scanning/blanking, swift-markdown parsing, source block/task mapping, and final HTML document assembly.
* Recognized comments are hidden from raw HTML and rendered as comment UI.
* Source/task `data-*` attributes are present.
* Existing renderer behavior remains intact except for intentional task checkbox interactivity.
* Rail is inside `#content`, copy-stripped, and excluded from find if the team keeps comment-card text out of find results.

### Worker C: WKWebView bridge

Owns:

* `Nex/Features/MarkdownPane/MarkdownPaneView.swift`
* `Nex/Features/MarkdownPane/MarkdownFindScript.swift`
* `Nex/Features/MarkdownPane/MarkdownReviewScript.swift`
* optional `Nex/Features/MarkdownPane/MarkdownReviewPayload.swift`
* optional `NexTests/MarkdownReviewPayloadTests.swift`

May depend on Worker A and B APIs.

Do not edit:

* `PaneHeaderView.swift`
* `PaneGridView.swift`
* renderer tests except compile fixes agreed with Worker B

Output contract:

* New script handler.
* Comment mode applied from Swift to JS.
* Add-comment and checkbox messages mutate `currentContent` and disk source.
* Optimistic checkbox rollback path exists.
* `MarkdownFindScript.shouldSkipNode` skips comment highlight and rail classes.
* `MarkdownPaneView.copyAsRichText` strips `.nex-comment-rail` before creating pasteboard HTML/RTF.
* Script handlers are explicitly removed during dismantle.
* Initializer shape for `MarkdownPaneView(commentModeEnabled:)` is published before Worker D updates the call site.

### Worker D: Header and pane wiring

Owns:

* `Nex/Features/PaneGrid/PaneHeaderView.swift`
* `Nex/Features/PaneGrid/PaneGridView.swift`
* `NexTests/WorkspaceFeatureTests.swift` only if state moves to reducer

Do not edit:

* renderer/source helper files
* `MarkdownPaneView.swift`

Output contract:

* Header comment-mode button visible only in markdown preview mode.
* `PaneGridView` keeps per-pane comment mode state.
* State is passed into `MarkdownPaneView` from the `PaneGridView` call site only, using Worker C's published initializer shape.
* Comment mode is cleared when preview is replaced by edit mode.

### Worker E: Integration and QA

Owns:

* compile fixes that cross boundaries after A-D merge
* focused test failures
* manual QA notes

Do not rewrite designs from other workers unless a compile or behavior issue requires it.

Output contract:

* All targeted markdown tests pass.
* Full test command has been attempted.
* Remaining failures, if any, are documented with exact commands and failure summaries.

## Risks and constraints

* `swift-markdown` source ranges may be relative to the front-matter-stripped body or nil. Carry explicit offsets and provide visit-order fallbacks.
* Partial text selection inside formatted inline markdown is intentionally not mapped back to source byte offsets in the MVP. The source marker is block-adjacent; exact highlighting is a rendered-DOM refinement from `anchorText`.
* HTML comments cannot contain `--`; use the documented reversible escape for user-controlled fields and test `--` / `-->` round trips.
* Current copy-as-markdown intentionally avoids selection-aware source mapping because previous block-level mapping was inconsistent. Do not revive selection-aware copy as part of this feature.
* Raw HTML pass-through exists today. Only transform recognized `nex-comment` blocks.
* Recognized `nex-comment` blocks must be line-isolated and outside fenced code. Inline-adjacent or fenced lookalikes must not be stripped.
* Checkbox mutation must preserve BOM, line endings, trailing-newline state, and unrelated file text.
* File watcher reloads must not fight optimistic updates. Keep `currentContent` synchronized before writing, write in place for the prototype, and serialize per-coordinator writes.
* Same-file multi-pane behavior depends on deterministic source block and task IDs across independent WK coordinators.

## Acceptance criteria

* Markdown preview can enter and exit comment mode from the pane header.
* Selecting simple rendered paragraph/list/heading text can create a comment.
* Ambiguous selections attach to the nearest rendered source block.
* Source receives a readable `<!-- nex-comment ... -->` block near the anchor.
* Rendered preview hides raw Nex comment syntax.
* Rendered preview shows a comment rail only when comments exist.
* Comment text is escaped, plain text, and round-trips through `--` / `-->`.
* Task checkboxes are clickable in view mode even when comment mode is off.
* Checkbox clicks optimistically update the DOM.
* Checkbox clicks write only the relevant markdown marker.
* Checkbox IDs are aligned to rendered swift-markdown task-list items and never toggle blockquoted or otherwise non-rendered task-looking text.
* Mutations preserve BOM, line endings, and trailing-newline state.
* Existing markdown rendering, front matter, copy, find, and edit mode behavior continue to work.
