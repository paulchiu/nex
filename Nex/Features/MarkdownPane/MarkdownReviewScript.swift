import Foundation

enum MarkdownReviewScript {
    static let source: String = """
    (function() {
      if (window.__nexMarkdownReview) { return; }

      var ns = {};
      window.__nexMarkdownReview = ns;
      ns.commentMode = false;
      ns.pendingTasks = {};
      ns.activeCommentID = null;
      ns.layoutFrame = null;
      ns.resizeObserver = null;

      var styleEl = document.createElement('style');
      styleEl.textContent = "body.nex-comment-mode { cursor: text; }";

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
        return !!el.closest('.\(MarkdownDOMClass.commentRail)');
      }

      function closestBlock(node) {
        var el = elementForNode(node);
        return el ? el.closest('[data-nex-block-id]') : null;
      }

      function rectPayload(rect) {
        return {
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height
        };
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
          rect: rectPayload(range.getBoundingClientRect())
        };
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

      function scrollElementIntoView(element, block) {
        if (!element) return;
        try {
          element.scrollIntoView({ block: block || 'nearest', inline: 'nearest', behavior: 'smooth' });
        } catch (_) {
          element.scrollIntoView(false);
        }
      }

      function setActiveComment(id, options) {
        options = options || {};
        removeActiveComment();
        ns.activeCommentID = id || null;
        if (!id) {
          scheduleCommentLayout();
          return;
        }

        var escaped = CSS.escape(id);
        var card = document.querySelector('.nex-comment-card[data-nex-comment-id="' + escaped + '"]');
        var target = null;
        if (card) {
          card.classList.add('\(MarkdownDOMClass.commentCardActive)');
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
          scrollElementIntoView(target, 'nearest');
        }
        positionCommentCards();
        if (options.scrollCard && card) {
          scrollElementIntoView(card, 'nearest');
        }
      }

      function onClick(event) {
        var target = elementForNode(event.target);
        if (!target) return;

        var edit = target.closest('[data-nex-comment-edit]');
        if (edit) {
          event.preventDefault();
          event.stopPropagation();
          var editCard = closestCommentCard(edit);
          if (editCard) {
            var body = editCard.querySelector('[data-nex-comment-body]');
            post({
              type: 'requestEditComment',
              commentID: editCard.getAttribute('data-nex-comment-id'),
              comment: body ? String(body.textContent || '') : '',
              rect: rectPayload(editCard.getBoundingClientRect())
            });
          }
          return;
        }

        var del = target.closest('[data-nex-comment-delete]');
        if (del) {
          event.preventDefault();
          event.stopPropagation();
          var deleteCard = closestCommentCard(del);
          if (deleteCard) {
            post({
              type: 'requestDeleteComment',
              commentID: deleteCard.getAttribute('data-nex-comment-id'),
              rect: rectPayload(deleteCard.getBoundingClientRect())
            });
          }
          return;
        }

        var card = closestCommentCard(target);
        if (card) {
          post({
            type: 'activateComment',
            commentID: card.getAttribute('data-nex-comment-id'),
            scrollTarget: true
          });
          return;
        }

        var highlight = target.closest('[data-nex-comment-highlight-id]');
        if (highlight) {
          post({
            type: 'activateComment',
            commentID: highlight.getAttribute('data-nex-comment-highlight-id'),
            scrollCard: true
          });
          return;
        }

        if (ns.activeCommentID) {
          post({ type: 'clearActiveComment' });
        }
      }

      function onKeyDown(event) {
        var target = elementForNode(event.target);
        if (!target || target.closest('button, textarea, input, select, a')) return;
        var card = closestCommentCard(target);
        if (!card) return;
        if (event.key !== 'Enter' && event.key !== ' ' && event.key !== 'Spacebar') return;
        event.preventDefault();
        post({
          type: 'activateComment',
          commentID: card.getAttribute('data-nex-comment-id'),
          scrollTarget: true
        });
      }

      function onMouseUp(event) {
        if (!ns.commentMode) return;
        if (isReviewChrome(event.target)) return;
        setTimeout(function() {
          var info = selectionInfo();
          if (info) {
            post({
              type: 'requestAddComment',
              selectedText: info.selectedText,
              blockID: info.blockID,
              rect: info.rect
            });
          }
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
            mobileCards[m].style.zIndex = '';
            mobileCards[m].classList.remove('nex-comment-card-suppressed');
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
          card.classList.remove('nex-comment-card-suppressed');
          card.style.zIndex = '';
          var target = targetForCommentCard(card);
          var y = 0;
          if (target) {
            y = target.getBoundingClientRect().top - railRect.top;
          }
          items.push({
            card: card,
            y: Math.max(0, y),
            active: ns.activeCommentID && card.getAttribute('data-nex-comment-id') === ns.activeCommentID
          });
        }

        items.sort(function(a, b) { return a.y - b.y; });
        var activeItem = null;
        for (var a = 0; a < items.length; a++) {
          if (items[a].active) {
            activeItem = items[a];
            break;
          }
        }
        var gap = 8;
        var suppressedHeight = 52;
        var activeTop = null;
        var activeBottom = null;
        var activeAboveCursor = null;
        var activeBelowCursor = null;
        if (activeItem) {
          activeTop = activeItem.y;
          activeItem.card.style.top = activeTop + 'px';
          activeItem.card.style.zIndex = '2';
          activeBottom = activeTop + activeItem.card.offsetHeight;
          activeAboveCursor = activeTop;
          activeBelowCursor = activeBottom + gap;
        }

        var cursor = 0;
        for (var j = 0; j < items.length; j++) {
          var item = items[j];
          if (item.active) {
            cursor = Math.max(cursor, activeBottom + gap);
            continue;
          }

          var height = item.card.offsetHeight;
          var collapsedHeight = Math.min(height, suppressedHeight);
          var top = Math.max(item.y, cursor);
          var displacedByActive = false;
          var effectiveHeight = height;
          if (activeItem) {
            var overlapsActive = top < activeBottom + gap && top + height + gap > activeTop;
            if (overlapsActive) {
              displacedByActive = true;
              effectiveHeight = collapsedHeight;
              if (item.y < activeTop && activeAboveCursor >= collapsedHeight + gap) {
                top = Math.max(0, activeAboveCursor - collapsedHeight - gap);
                activeAboveCursor = top;
              } else {
                top = activeBelowCursor;
                activeBelowCursor = top + collapsedHeight + gap;
              }
            } else if (Math.abs(top - item.y) > 16) {
              displacedByActive = true;
              effectiveHeight = collapsedHeight;
            }
          }

          item.card.style.top = top + 'px';
          if (displacedByActive) {
            item.card.classList.add('nex-comment-card-suppressed');
          }
          cursor = top + effectiveHeight + gap;
        }

        var requiredHeight = Math.max(cursor, activeBottom || 0);
        if (requiredHeight > baseHeight) {
          rail.style.minHeight = requiredHeight + 'px';
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
      };

      ns.setActiveComment = function(id, options) {
        setActiveComment(id, options || {});
      };

      ns.clearSelection = function() {
        var sel = window.getSelection();
        if (sel) sel.removeAllRanges();
      };

      ns.revertTask = function(taskID, checked) {
        var input = document.querySelector('input.task-list-item-checkbox[data-nex-task-id="' + CSS.escape(taskID) + '"]');
        if (input) input.checked = !!checked;
        delete ns.pendingTasks[taskID];
      };

      ns.confirmTask = function(taskID) {
        delete ns.pendingTasks[taskID];
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
