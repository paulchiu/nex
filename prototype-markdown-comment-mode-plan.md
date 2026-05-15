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

Store comments as one YAML-ish HTML comment block after the selected source text or nearest source block:

```markdown
This is the selected sentence.

<!-- nex-comment
id: "nex-20260515-103122-a83f"
createdAt: "2026-05-15T10:31:22Z"
anchorStrategy: "exact-selection"
anchorText: |-
  This is the selected sentence.
anchorHash: "sha256:..."
sourceBlockHash: "sha256:..."
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
sourceBlockHash: "sha256:..."
comment: |-
  This applies to the nearby paragraph.
-->
```

Notes:

* Keep all comment fields plain text.
* Escape or normalize `--` inside user comment fields before writing, because `--` is invalid inside HTML comments.
* Use Yams if convenient, since the app already depends on it. If the parser is too strict for malformed blocks, fail closed: hide the raw Nex comment and render a small "Malformed Nex comment" card rather than exposing source syntax.
* Unknown HTML comments should keep current behavior.

## Recommended architecture

### 1. Source model and mutations

Add source-level helpers under `Nex/Features/MarkdownPane/`:

* `MarkdownComment.swift`
  * `MarkdownComment`
  * `MarkdownCommentParser`
  * comment block serialization
  * comment field escaping/sanitization
* `MarkdownSourceMap.swift`
  * line start index
  * byte/range helpers
  * front-matter body offset metadata
  * source block identity/hash helpers
  * task marker discovery
* `MarkdownSourceMutations.swift`
  * `insertComment(...)`
  * `toggleTaskCheckbox(...)`

Important constraint: mutation helpers should replace only the exact source region required. Do not reserialize the full markdown document.

For task checkboxes, pre-scan source lines with a marker regex that covers unordered and ordered task items:

```regex
^\s*(?:[-+*]|\d+[.)])\s+\[[ xX]\]
```

Each rendered checkbox should get a `data-nex-task-id` that maps back to the pre-scanned marker. The click handler should post `taskID` and desired checked state, not raw line text.

### 2. Render context

Introduce a render context object rather than making the renderer infer everything from HTML strings:

```swift
struct MarkdownRenderContext {
    var comments: [MarkdownComment]
    var taskMarkers: [MarkdownTaskMarker]
    var sourceBlocks: [MarkdownSourceBlock]
}
```

The public renderer can preserve the current convenience API:

```swift
MarkdownRenderer.renderToHTML(markdown, ...)
```

But internally it should build a source model first:

1. Extract front matter with existing `FrontMatterExtractor`.
2. Parse recognized `<!-- nex-comment ... -->` blocks.
3. Remove or blank recognized comment blocks before swift-markdown parsing so raw Nex comment syntax does not appear as DOM comments.
4. Preserve line numbering by replacing removed comment blocks with equivalent newlines.
5. Parse the cleaned body with swift-markdown.
6. Emit `data-nex-block-id` / source metadata on supported blocks.
7. Emit a comment rail/callout from the parsed comment list.

The front-matter offset matters. Current parsing strips front matter before `Document(parsing: body)`, so any source ranges from swift-markdown are relative to the stripped body. Either carry body line/byte offset explicitly, or use a line-based source scanner for MVP source block IDs.

### 3. Comment rendering

The prototype should render:

* Highlight around the exact selected text when it can be found inside the anchor block.
* Whole-block highlight when exact text matching fails.
* Comment rail only when at least one comment exists.
* Comment cards as escaped plain text.

Implementation options:

* Renderer emits comment cards and a JSON manifest; injected JS applies exact text highlights post-load.
* Renderer emits whole-block highlights directly; JS refines to exact text highlight if possible.

Prefer the second option for MVP. It has a useful fallback even when JS text range matching fails.

### 4. WKWebView bridge

Add a new script handler next to `scrollHandler` and `nexFind` in `MarkdownPaneView.makeNSView`:

```swift
config.userContentController.add(handler, name: "nexMarkdownReview")
```

Add `MarkdownReviewScript.swift`, mirroring the style of `MarkdownFindScript.swift`.

The script should handle:

* Comment mode on/off.
* Selection capture from `window.getSelection()`.
* Nearest `data-nex-block-id` lookup.
* Add-comment popover in the DOM.
* Checkbox click listeners.
* Optimistic checkbox updates.
* Failure rollback hook, e.g. `window.__nexMarkdownReview.revertTask(taskID, checked)`.

Messages to Swift:

```json
{
  "type": "addComment",
  "selectedText": "...",
  "blockID": "...",
  "selectionStartTextOffset": 12,
  "selectionEndTextOffset": 42,
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
* Write the changed file with UTF-8, atomically.
* Re-render immediately after successful comment insertion.
* For checkbox toggles, avoid full reload when possible; optimistic DOM update is enough, and the file watcher will see unchanged `currentContent` after the write.
* On write failure, ask JS to revert the checkbox or show a small error state.

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
* Strip or blank recognized comment blocks for rendering.
* Build source line index and source block/task marker maps.
* Toggle task marker mutation without full document rewrite.
* Insert comment block after exact selected source span or nearest block.

Tests:

* Parse valid comment block.
* Malformed comment block is handled safely.
* Unknown HTML comment remains unknown.
* Insert exact-selection comment after target source.
* Insert nearest-block comment after nearest block.
* Toggle unchecked, checked lowercase, checked uppercase.
* Preserve indentation, list marker, line endings, and unrelated text.

### Phase 2: Renderer

Deliver:

* `MarkdownRenderer` consumes the source model.
* Recognized Nex comment blocks are hidden as raw syntax.
* Comment cards/rail render only when comments exist.
* Supported block tags get stable `data-nex-block-id`.
* Task checkboxes get `data-nex-task-id` and are no longer disabled.
* Checkbox cursor changes from default to pointer.
* Existing front matter rendering still works.
* Existing unknown raw HTML behavior is preserved.

Tests:

* Existing `MarkdownHTMLRendererTests` and `MarkdownCheckboxRenderingTests` still pass, updated only for intentional attribute changes.
* Nex comment block is not present as raw `<!-- nex-comment` in rendered HTML.
* Comment text is escaped.
* Comment rail is absent when there are no comments.
* Comment rail is present when comments exist.
* Task checkbox contains `data-nex-task-id`.
* Front matter plus comments keeps correct body behavior.

### Phase 3: WK bridge

Deliver:

* Inject `MarkdownReviewScript`.
* Add `nexMarkdownReview` handler.
* Toggle script mode from `MarkdownPaneView.updateNSView`.
* Capture selection and nearest source block.
* Show add-comment DOM popover.
* Post add-comment and toggle-task messages to Swift.
* Mutate source through helpers.
* Re-render after comment insertion.
* Optimistically toggle checkbox and roll back on write failure.

Tests:

* Unit-test Swift message parsing if extracted into a small payload type.
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
4. Toggle comment mode.
5. Select text inside one paragraph and add a comment.
6. Confirm a `nex-comment` block is inserted near the source.
7. Confirm the raw comment syntax is hidden in preview.
8. Confirm the comment rail appears.
9. Select text spanning multiple rendered blocks.
10. Confirm Nex attaches a nearest-block comment rather than failing.

## Subagent implementation plan

The following split is designed to avoid overlapping write sets.

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

* Public helpers for comment parse/serialize.
* Public helpers for task marker discovery and mutation.
* Public helper for comment insertion from a block/selection payload.

### Worker B: Renderer and HTML/CSS

Owns:

* `Nex/Features/MarkdownPane/MarkdownHTMLRenderer.swift`
* `NexTests/MarkdownHTMLRendererTests.swift`
* `NexTests/MarkdownCheckboxRenderingTests.swift`

May depend on Worker A public types. If Worker A is not merged yet, define against a small agreed protocol/initializer shape and leave compile fixes for integration.

Do not edit:

* `MarkdownPaneView.swift`
* pane header/grid files

Output contract:

* Recognized comments are hidden from raw HTML and rendered as comment UI.
* Source/task `data-*` attributes are present.
* Existing renderer behavior remains intact except for intentional task checkbox interactivity.

### Worker C: WKWebView bridge

Owns:

* `Nex/Features/MarkdownPane/MarkdownPaneView.swift`
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

### Worker D: Header and pane wiring

Owns:

* `Nex/Features/PaneGrid/PaneHeaderView.swift`
* `Nex/Features/PaneGrid/PaneGridView.swift`
* `NexTests/WorkspaceFeatureTests.swift` only if state moves to reducer

Do not edit:

* renderer/source helper files
* `MarkdownPaneView.swift` except initializer call-site compile fixes

Output contract:

* Header comment-mode button visible only in markdown preview mode.
* `PaneGridView` keeps per-pane comment mode state.
* State is passed into `MarkdownPaneView`.
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

* `swift-markdown` source ranges may be relative to the front-matter-stripped body. Carry explicit offsets.
* Partial text selection inside formatted inline markdown is hard to map exactly. MVP may attach to the block and store selected rendered text.
* HTML comments cannot contain `--`; sanitize comment fields before writing.
* Current copy-as-markdown intentionally avoids selection-aware source mapping because previous block-level mapping was inconsistent. Do not revive selection-aware copy as part of this feature.
* Raw HTML pass-through exists today. Only transform recognized `nex-comment` blocks.
* Checkbox mutation must preserve line endings and unrelated file text.
* File watcher reloads must not fight optimistic updates. Keep `currentContent` synchronized before writing.

## Acceptance criteria

* Markdown preview can enter and exit comment mode from the pane header.
* Selecting simple rendered paragraph/list/heading text can create a comment.
* Ambiguous selections attach to the nearest rendered source block.
* Source receives a readable `<!-- nex-comment ... -->` block near the anchor.
* Rendered preview hides raw Nex comment syntax.
* Rendered preview shows a comment rail only when comments exist.
* Comment text is escaped and plain text.
* Task checkboxes are clickable in view mode even when comment mode is off.
* Checkbox clicks optimistically update the DOM.
* Checkbox clicks write only the relevant markdown marker.
* Existing markdown rendering, front matter, copy, find, and edit mode behavior continue to work.
