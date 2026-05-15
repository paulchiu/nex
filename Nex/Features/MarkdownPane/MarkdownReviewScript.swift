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
      ns.layoutFrame = null;
      ns.resizeObserver = null;

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

      function isCommandEnter(event) {
        return event.metaKey && (event.key === 'Enter' || event.key === 'NumpadEnter');
      }

      function onPopoverKeyDown(event) {
        if (event.key !== 'Escape') return;
        event.preventDefault();
        event.stopPropagation();
        removePopover();
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
        var commonBlock = closestBlock(range.commonAncestorContainer);
        var block = commonBlock || startBlock;
        if (!block) return null;
        if (isReviewChrome(block)) return null;
        return {
          selectedText: selectedText,
          blockID: block.getAttribute('data-nex-block-id'),
          rect: range.getBoundingClientRect()
        };
      }

      function showPopover(info) {
        removePopover();
        var pop = document.createElement('div');
        pop.className = 'nex-review-popover';
        pop.addEventListener('keydown', onPopoverKeyDown);
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

        var top = Math.max(8, Math.min(info.rect.bottom + 8, window.innerHeight - pop.offsetHeight - 8));
        var left = Math.max(8, Math.min(info.rect.left, window.innerWidth - 300));
        pop.style.top = top + 'px';
        pop.style.left = left + 'px';

        function submitComment() {
          var comment = String(textarea.value || '').trim();
          if (!comment) { textarea.focus(); return; }
          post({
            type: 'addComment',
            selectedText: info.selectedText,
            blockID: info.blockID,
            comment: comment
          });
          removePopover();
          var sel = window.getSelection();
          if (sel) sel.removeAllRanges();
        }

        cancel.addEventListener('click', removePopover);
        add.addEventListener('click', submitComment);
        textarea.addEventListener('keydown', function(event) {
          if (!isCommandEnter(event)) return;
          event.preventDefault();
          submitComment();
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
        pop.addEventListener('keydown', onPopoverKeyDown);
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
        pop.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - pop.offsetHeight - 8)) + 'px';
        pop.style.left = Math.max(8, Math.min(rect.left - 292, window.innerWidth - 300)) + 'px';

        function submitEdit() {
          var comment = String(textarea.value || '').trim();
          if (!comment) { textarea.focus(); return; }
          post({
            type: 'updateComment',
            commentID: card.getAttribute('data-nex-comment-id'),
            comment: comment
          });
          removePopover();
        }

        cancel.addEventListener('click', removePopover);
        save.addEventListener('click', submitEdit);
        textarea.addEventListener('keydown', function(event) {
          if (!isCommandEnter(event)) return;
          event.preventDefault();
          submitEdit();
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
        pop.addEventListener('keydown', onPopoverKeyDown);
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
        pop.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - pop.offsetHeight - 8)) + 'px';
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
        cancel.focus();
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
        if (ns.popover && !ns.popover.contains(target)) removePopover();

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

      function onKeyDown(event) {
        var target = elementForNode(event.target);
        if (!target || target.closest('button, textarea, input, select, a')) return;
        var card = closestCommentCard(target);
        if (!card) return;
        if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
        event.preventDefault();
        setActiveComment(card.getAttribute('data-nex-comment-id'), { scrollTarget: true });
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
          var range = uniqueTextRange(textNodesFor(block), anchor);
          if (!range) continue;
          wrapTextRange(range, id);
        }
      }

      function uniqueTextRange(nodes, anchor) {
        var text = '';
        var segments = [];
        for (var i = 0; i < nodes.length; i++) {
          var value = nodes[i].nodeValue || '';
          segments.push({ node: nodes[i], start: text.length, end: text.length + value.length });
          text += value;
        }
        var start = text.indexOf(anchor);
        if (start < 0) return null;
        if (text.indexOf(anchor, start + anchor.length) >= 0) return null;
        return { start: start, end: start + anchor.length, segments: segments };
      }

      function wrapTextRange(range, id) {
        for (var i = 0; i < range.segments.length; i++) {
          var segment = range.segments[i];
          var start = Math.max(range.start, segment.start) - segment.start;
          var end = Math.min(range.end, segment.end) - segment.start;
          if (start < end) {
            wrapTextNodeSegment(segment.node, start, end, id);
          }
        }
      }

      function wrapTextNodeSegment(node, start, end, id) {
        var text = node.nodeValue || '';
        var parent = node.parentNode;
        if (!parent) return;
        var before = text.slice(0, start);
        var match = text.slice(start, end);
        var after = text.slice(end);
        if (!match) return;
        if (before) parent.insertBefore(document.createTextNode(before), node);
        parent.insertBefore(commentHighlightElement(match, id), node);
        if (after) parent.insertBefore(document.createTextNode(after), node);
        parent.removeChild(node);
      }

      function commentHighlightElement(text, id) {
        var span = document.createElement('span');
        span.className = '\(MarkdownDOMClass.commentHighlight)';
        span.setAttribute('data-nex-comment-highlight-id', id);
        span.appendChild(document.createTextNode(text));
        return span;
      }

      function targetForCommentCard(card) {
        var id = card.getAttribute('data-nex-comment-id');
        var blockID = card.getAttribute('data-nex-comment-block-id');
        if (!id) return null;

        var highlight = document.querySelector('[data-nex-comment-highlight-id="' + CSS.escape(id) + '"]');
        if (highlight) return highlight;
        if (!blockID) return null;
        return document.querySelector('[data-nex-block-id="' + CSS.escape(blockID) + '"]');
      }

      function positionCommentCards() {
        var rail = document.querySelector('.\(MarkdownDOMClass.commentRail)');
        var main = document.querySelector('.nex-markdown-main');
        if (!rail || !main) return;

        if (window.matchMedia && window.matchMedia('(max-width: 320px)').matches) {
          rail.classList.remove('nex-comment-rail-positioned');
          rail.style.minHeight = '';
          var mobileCards = rail.querySelectorAll('.nex-comment-card');
          for (var m = 0; m < mobileCards.length; m++) {
            mobileCards[m].style.top = '';
          }
          return;
        }

        var bodyStyle = window.getComputedStyle(document.body);
        var verticalPadding = parseFloat(bodyStyle.paddingTop || '0') + parseFloat(bodyStyle.paddingBottom || '0');
        var viewportHeight = Math.max(0, window.innerHeight - verticalPadding);
        var baseHeight = Math.max(main.scrollHeight, main.getBoundingClientRect().height, viewportHeight);
        rail.style.minHeight = baseHeight + 'px';
        rail.classList.add('nex-comment-rail-positioned');

        var railRect = rail.getBoundingClientRect();
        var cards = Array.prototype.slice.call(rail.querySelectorAll('.nex-comment-card'));
        var items = [];
        for (var i = 0; i < cards.length; i++) {
          var card = cards[i];
          var target = targetForCommentCard(card);
          var y = 0;
          if (target) {
            y = target.getBoundingClientRect().top - railRect.top;
          }
          items.push({ card: card, y: Math.max(0, y) });
        }

        items.sort(function(a, b) { return a.y - b.y; });
        var cursor = 0;
        for (var j = 0; j < items.length; j++) {
          var item = items[j];
          var top = Math.max(item.y, cursor);
          item.card.style.top = top + 'px';
          cursor = top + item.card.offsetHeight + 8;
        }

        if (cursor > baseHeight) {
          rail.style.minHeight = cursor + 'px';
        }
      }

      function refreshCommentLayout() {
        refineCommentHighlights();
        positionCommentCards();
      }

      function scheduleCommentLayout() {
        if (ns.layoutFrame !== null) return;
        ns.layoutFrame = requestAnimationFrame(function() {
          ns.layoutFrame = null;
          refreshCommentLayout();
        });
      }

      function watchLateLayoutChanges() {
        var main = document.querySelector('.nex-markdown-main');
        if (!main) return;
        if (window.ResizeObserver) {
          ns.resizeObserver = new ResizeObserver(scheduleCommentLayout);
          ns.resizeObserver.observe(main);
        }
        var images = main.querySelectorAll('img');
        for (var i = 0; i < images.length; i++) {
          if (images[i].complete) continue;
          images[i].addEventListener('load', scheduleCommentLayout, { once: true });
          images[i].addEventListener('error', scheduleCommentLayout, { once: true });
        }
        if (document.fonts && document.fonts.ready) {
          document.fonts.ready.then(scheduleCommentLayout);
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
      document.addEventListener('keydown', onKeyDown, true);
      document.addEventListener('change', onTaskChange, true);
      window.addEventListener('resize', scheduleCommentLayout);
      window.addEventListener('load', scheduleCommentLayout);
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
          refreshCommentLayout();
          watchLateLayoutChanges();
        }, { once: true });
      } else {
        refreshCommentLayout();
        watchLateLayoutChanges();
      }
    })();
    """
}
