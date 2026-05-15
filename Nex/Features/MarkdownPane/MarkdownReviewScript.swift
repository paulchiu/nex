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
      ns.activeCommentID = null;

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

      function closestCommentCard(node) {
        var el = elementForNode(node);
        return el ? el.closest('.nex-comment-card[data-nex-comment-id]') : null;
      }

      function isReviewChrome(node) {
        var el = elementForNode(node);
        if (!el) return false;
        return !!el.closest('.\(MarkdownDOMClass.commentRail), .nex-review-popover');
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
        if (isReviewChrome(range.startContainer) || isReviewChrome(range.endContainer) ||
            isReviewChrome(range.commonAncestorContainer)) {
          return null;
        }
        var startBlock = closestBlock(range.startContainer);
        var endBlock = closestBlock(range.endContainer);
        var commonBlock = closestBlock(range.commonAncestorContainer);
        var block = commonBlock || startBlock;
        if (!block) return null;
        if (isReviewChrome(block)) return null;
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

      function showEditPopover(card) {
        if (!card) return;
        removePopover();
        setActiveComment(card.getAttribute('data-nex-comment-id'), { scrollTarget: true });
        var pop = document.createElement('div');
        pop.className = 'nex-review-popover';
        var textarea = document.createElement('textarea');
        var body = card.querySelector('[data-nex-comment-body]');
        textarea.value = body ? String(body.textContent || '') : '';
        var actions = document.createElement('div');
        actions.className = 'nex-review-actions';
        var cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.textContent = 'Cancel';
        var save = document.createElement('button');
        save.type = 'button';
        save.className = 'primary';
        save.textContent = 'Save';
        actions.appendChild(cancel);
        actions.appendChild(save);
        pop.appendChild(textarea);
        pop.appendChild(actions);
        document.body.appendChild(pop);

        var rect = card.getBoundingClientRect();
        pop.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - 130)) + 'px';
        pop.style.left = Math.max(8, Math.min(rect.left - 292, window.innerWidth - 300)) + 'px';

        cancel.addEventListener('click', removePopover);
        save.addEventListener('click', function() {
          var comment = String(textarea.value || '').trim();
          if (!comment) { textarea.focus(); return; }
          post({
            type: 'updateComment',
            commentID: card.getAttribute('data-nex-comment-id'),
            comment: comment
          });
          removePopover();
        });

        ns.popover = pop;
        textarea.focus();
        textarea.select();
      }

      function showDeletePopover(card) {
        if (!card) return;
        removePopover();
        setActiveComment(card.getAttribute('data-nex-comment-id'), { scrollTarget: true });
        var pop = document.createElement('div');
        pop.className = 'nex-review-popover';
        var message = document.createElement('div');
        message.textContent = 'Delete this comment?';
        var actions = document.createElement('div');
        actions.className = 'nex-review-actions';
        var cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.textContent = 'Cancel';
        var del = document.createElement('button');
        del.type = 'button';
        del.className = 'primary';
        del.textContent = 'Delete';
        actions.appendChild(cancel);
        actions.appendChild(del);
        pop.appendChild(message);
        pop.appendChild(actions);
        document.body.appendChild(pop);

        var rect = card.getBoundingClientRect();
        pop.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - 100)) + 'px';
        pop.style.left = Math.max(8, Math.min(rect.left - 292, window.innerWidth - 300)) + 'px';

        cancel.addEventListener('click', removePopover);
        del.addEventListener('click', function() {
          post({
            type: 'deleteComment',
            commentID: card.getAttribute('data-nex-comment-id')
          });
          removePopover();
        });

        ns.popover = pop;
        del.focus();
      }

      function removeActiveComment() {
        var active = document.querySelectorAll(
          '.\(MarkdownDOMClass.commentCardActive), .\(MarkdownDOMClass.commentHighlightActive), .\(MarkdownDOMClass.commentBlockActive)'
        );
        for (var i = 0; i < active.length; i++) {
          active[i].classList.remove(
            '\(MarkdownDOMClass.commentCardActive)',
            '\(MarkdownDOMClass.commentHighlightActive)',
            '\(MarkdownDOMClass.commentBlockActive)'
          );
        }
      }

      function setActiveComment(id, options) {
        options = options || {};
        removeActiveComment();
        ns.activeCommentID = id || null;
        if (!id) return;

        var escaped = CSS.escape(id);
        var card = document.querySelector('.nex-comment-card[data-nex-comment-id="' + escaped + '"]');
        var target = null;
        if (card) {
          card.classList.add('\(MarkdownDOMClass.commentCardActive)');
          if (options.scrollCard) {
            card.scrollIntoView({ block: 'nearest', inline: 'nearest' });
          }
          var blockID = card.getAttribute('data-nex-comment-block-id');
          if (blockID) {
            var block = document.querySelector('[data-nex-block-id="' + CSS.escape(blockID) + '"]');
            if (block) {
              block.classList.add('\(MarkdownDOMClass.commentBlockActive)');
              target = block;
            }
          }
        }

        var highlights = document.querySelectorAll('[data-nex-comment-highlight-id="' + escaped + '"]');
        for (var i = 0; i < highlights.length; i++) {
          highlights[i].classList.add('\(MarkdownDOMClass.commentHighlightActive)');
          if (!target) target = highlights[i];
        }
        if (options.scrollTarget && target) {
          target.scrollIntoView({ block: 'center', inline: 'nearest' });
        }
      }

      function onClick(event) {
        var target = elementForNode(event.target);
        if (!target) return;

        var edit = target.closest('[data-nex-comment-edit]');
        if (edit) {
          event.preventDefault();
          event.stopPropagation();
          showEditPopover(closestCommentCard(edit));
          return;
        }

        var del = target.closest('[data-nex-comment-delete]');
        if (del) {
          event.preventDefault();
          event.stopPropagation();
          showDeletePopover(closestCommentCard(del));
          return;
        }

        var card = closestCommentCard(target);
        if (card) {
          setActiveComment(card.getAttribute('data-nex-comment-id'), { scrollTarget: true });
          return;
        }

        var highlight = target.closest('[data-nex-comment-highlight-id]');
        if (highlight) {
          setActiveComment(highlight.getAttribute('data-nex-comment-highlight-id'), { scrollCard: true });
        }
      }

      function onMouseUp(event) {
        if (!ns.commentMode) return;
        if (ns.popover && ns.popover.contains(event.target)) return;
        if (isReviewChrome(event.target)) return;
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
          var blockID = card.getAttribute('data-nex-comment-block-id');
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
      document.addEventListener('click', onClick, true);
      document.addEventListener('change', onTaskChange, true);
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', refineCommentHighlights, { once: true });
      } else {
        refineCommentHighlights();
      }
    })();
    """
}
