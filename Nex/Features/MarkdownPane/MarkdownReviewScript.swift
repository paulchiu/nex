import Foundation

enum MarkdownReviewScript {
    static let source: String = """
    (function() {
      if (window.__nexMarkdownReview) { return; }

      var ns = {};
      window.__nexMarkdownReview = ns;
      ns.commentMode = false;
      ns.pendingTasks = {};
      ns.popover = null;

      var styleEl = document.createElement('style');
      styleEl.textContent = (
        "body.nex-comment-mode { cursor: text; }" +
        ".nex-review-popover { position: fixed; z-index: 2147483647; width: 280px; border: 1px solid #d1d9e0; border-radius: 8px; background: #fff; color: #1f2328; box-shadow: 0 12px 30px rgba(0,0,0,.18); padding: 8px; font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; }" +
        ".dark .nex-review-popover { background: #161b22; color: #e6edf3; border-color: #3d444d; }" +
        ".nex-review-popover textarea { box-sizing: border-box; width: 100%; min-height: 76px; resize: vertical; border: 1px solid #d1d9e0; border-radius: 6px; padding: 6px; font: inherit; color: inherit; background: transparent; }" +
        ".dark .nex-review-popover textarea { border-color: #3d444d; }" +
        ".nex-review-actions { display: flex; justify-content: flex-end; gap: 6px; margin-top: 6px; }" +
        ".nex-review-actions button { border: 1px solid #d1d9e0; border-radius: 5px; background: #f6f8fa; color: inherit; padding: 3px 8px; font: inherit; cursor: pointer; }" +
        ".dark .nex-review-actions button { border-color: #3d444d; background: #21262d; }" +
        ".nex-review-actions button.primary { background: #0969da; border-color: #0969da; color: #fff; }"
      );

      function injectStyle() {
        if (document.head) {
          document.head.appendChild(styleEl);
        } else {
          requestAnimationFrame(injectStyle);
        }
      }
      injectStyle();

      function handler() {
        return window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.nexMarkdownReview;
      }

      function post(payload) {
        var h = handler();
        if (h) h.postMessage(payload);
      }

      function removePopover() {
        if (ns.popover && ns.popover.parentNode) {
          ns.popover.parentNode.removeChild(ns.popover);
        }
        ns.popover = null;
      }

      function elementForNode(node) {
        if (!node) return null;
        return node.nodeType === 1 ? node : node.parentElement;
      }

      function closestBlock(node) {
        var el = elementForNode(node);
        return el ? el.closest('[data-nex-block-id]') : null;
      }

      function selectionInfo() {
        var sel = window.getSelection();
        if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
        var selectedText = String(sel.toString() || '').trim();
        if (!selectedText) return null;
        var range = sel.getRangeAt(0);
        var startBlock = closestBlock(range.startContainer);
        var endBlock = closestBlock(range.endContainer);
        var commonBlock = closestBlock(range.commonAncestorContainer);
        var block = commonBlock || startBlock;
        if (!block) return null;
        var strategy = (startBlock && endBlock && startBlock === endBlock && commonBlock)
          ? 'exact-selection'
          : 'nearest-block';
        return {
          selectedText: selectedText,
          blockID: block.getAttribute('data-nex-block-id'),
          anchorStrategy: strategy,
          rect: range.getBoundingClientRect()
        };
      }

      function showPopover(info) {
        removePopover();
        var pop = document.createElement('div');
        pop.className = 'nex-review-popover';
        var textarea = document.createElement('textarea');
        textarea.placeholder = 'Comment';
        var actions = document.createElement('div');
        actions.className = 'nex-review-actions';
        var cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.textContent = 'Cancel';
        var add = document.createElement('button');
        add.type = 'button';
        add.className = 'primary';
        add.textContent = 'Add';
        actions.appendChild(cancel);
        actions.appendChild(add);
        pop.appendChild(textarea);
        pop.appendChild(actions);
        document.body.appendChild(pop);

        var top = Math.max(8, info.rect.bottom + 8);
        var left = Math.max(8, Math.min(info.rect.left, window.innerWidth - 300));
        pop.style.top = top + 'px';
        pop.style.left = left + 'px';

        cancel.addEventListener('click', removePopover);
        add.addEventListener('click', function() {
          var comment = String(textarea.value || '').trim();
          if (!comment) { textarea.focus(); return; }
          post({
            type: 'addComment',
            selectedText: info.selectedText,
            blockID: info.blockID,
            anchorStrategy: info.anchorStrategy,
            comment: comment
          });
          removePopover();
          var sel = window.getSelection();
          if (sel) sel.removeAllRanges();
        });

        ns.popover = pop;
        textarea.focus();
      }

      function onMouseUp(event) {
        if (!ns.commentMode) return;
        if (ns.popover && ns.popover.contains(event.target)) return;
        setTimeout(function() {
          var info = selectionInfo();
          if (info) showPopover(info);
        }, 0);
      }

      function onTaskChange(event) {
        var input = event.target;
        if (!input || !input.matches || !input.matches('input.task-list-item-checkbox[data-nex-task-id]')) {
          return;
        }
        var taskID = input.getAttribute('data-nex-task-id');
        if (!taskID || ns.pendingTasks[taskID]) {
          event.preventDefault();
          input.checked = !input.checked;
          return;
        }
        ns.pendingTasks[taskID] = true;
        post({ type: 'toggleTask', taskID: taskID, checked: !!input.checked });
      }

      function skipHighlightNode(node) {
        var p = node.parentNode;
        while (p) {
          if (p.nodeType !== 1) { p = p.parentNode; continue; }
          if (p.classList && (
              p.classList.contains('\(MarkdownDOMClass.findMatch)') ||
              p.classList.contains('\(MarkdownDOMClass.commentHighlight)') ||
              p.classList.contains('\(MarkdownDOMClass.commentRail)')
          )) return true;
          p = p.parentNode;
        }
        return false;
      }

      function textNodesFor(block) {
        var walker = document.createTreeWalker(
          block,
          NodeFilter.SHOW_TEXT,
          {
            acceptNode: function(node) {
              if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
              if (skipHighlightNode(node)) return NodeFilter.FILTER_REJECT;
              return NodeFilter.FILTER_ACCEPT;
            }
          }
        );
        var nodes = [];
        var n;
        while ((n = walker.nextNode())) nodes.push(n);
        return nodes;
      }

      function refineCommentHighlights() {
        var cards = document.querySelectorAll('.\(MarkdownDOMClass.commentRail) [data-nex-comment-id]');
        for (var i = 0; i < cards.length; i++) {
          var card = cards[i];
          var id = card.getAttribute('data-nex-comment-id');
          var blockID = card.getAttribute('data-nex-block-id');
          var anchor = card.getAttribute('data-nex-anchor-text') || '';
          if (!id || !blockID || !anchor) continue;
          var block = document.querySelector('[data-nex-block-id="' + CSS.escape(blockID) + '"]');
          if (!block || block.querySelector('[data-nex-comment-highlight-id="' + CSS.escape(id) + '"]')) {
            continue;
          }
          var nodes = textNodesFor(block);
          var target = null;
          var targetIndex = -1;
          var count = 0;
          for (var n = 0; n < nodes.length; n++) {
            var idx = nodes[n].nodeValue.indexOf(anchor);
            if (idx >= 0) {
              count += 1;
              target = nodes[n];
              targetIndex = idx;
            }
          }
          if (count !== 1 || !target) continue;
          var text = target.nodeValue;
          var before = text.slice(0, targetIndex);
          var match = text.slice(targetIndex, targetIndex + anchor.length);
          var after = text.slice(targetIndex + anchor.length);
          var span = document.createElement('span');
          span.className = '\(MarkdownDOMClass.commentHighlight)';
          span.setAttribute('data-nex-comment-highlight-id', id);
          span.appendChild(document.createTextNode(match));
          var parent = target.parentNode;
          if (before) parent.insertBefore(document.createTextNode(before), target);
          parent.insertBefore(span, target);
          if (after) parent.insertBefore(document.createTextNode(after), target);
          parent.removeChild(target);
        }
      }

      ns.setCommentMode = function(enabled) {
        ns.commentMode = !!enabled;
        if (document.body) {
          document.body.classList.toggle('nex-comment-mode', ns.commentMode);
        }
        if (!ns.commentMode) removePopover();
      };

      ns.revertTask = function(taskID, checked) {
        var input = document.querySelector('input.task-list-item-checkbox[data-nex-task-id="' + CSS.escape(taskID) + '"]');
        if (input) input.checked = !!checked;
        delete ns.pendingTasks[taskID];
      };

      ns.confirmTask = function(taskID) {
        delete ns.pendingTasks[taskID];
      };

      ns.showError = function(message) {
        removePopover();
        var pop = document.createElement('div');
        pop.className = 'nex-review-popover';
        pop.textContent = message || 'Markdown update failed';
        document.body.appendChild(pop);
        pop.style.top = '12px';
        pop.style.right = '12px';
        ns.popover = pop;
        setTimeout(removePopover, 2400);
      };

      document.addEventListener('mouseup', onMouseUp, true);
      document.addEventListener('change', onTaskChange, true);
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', refineCommentHighlights, { once: true });
      } else {
        refineCommentHighlights();
      }
    })();
    """
}
