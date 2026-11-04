// Feedless page script for instagram.com. Injected at document start in every frame.
// Reads window.__feedless ({ feed, categories }) set by the native prelude and keeps
// <html data-fl-*> attributes in sync so instagram.css can do the hiding.
(function () {
  'use strict';
  if (window.__feedlessLoaded) { return; }
  window.__feedlessLoaded = true;

  var FEED_VARIANTS = ['following', 'favorites'];
  var HIDDEN_ATTR = 'data-fl-hidden';
  var DEBOUNCE_MS = 150;
  var MAX_CLIMB = 12;

  var config = window.__feedless || { feed: 'following', categories: {} };
  var html = document.documentElement;
  var scheduled = null;

  function enabled(category) {
    return config.categories[category] !== false;
  }

  function homePath() {
    return '/?variant=' + (FEED_VARIANTS.indexOf(config.feed) >= 0 ? config.feed : 'following');
  }

  function setPathAttribute() {
    html.setAttribute('data-fl-path', location.pathname);
  }

  // ---- Navigation --------------------------------------------------------
  // Instagram is a single-page app, so most taps never reach WKNavigationDelegate.
  function enforceLocation() {
    setPathAttribute();
    if (window !== window.top) { return; }
    var path = location.pathname;
    if (path.indexOf('/reels/') === 0 || path === '/explore/' || path === '/explore') {
      location.replace(homePath());
      return;
    }
    if (path === '/' || path === '') {
      var variant = new URLSearchParams(location.search).get('variant');
      if (FEED_VARIANTS.indexOf(variant) < 0) {
        location.replace(homePath());
      }
    }
  }

  function hookHistory(method) {
    var original = history[method];
    history[method] = function () {
      var result = original.apply(this, arguments);
      enforceLocation();
      schedule();
      return result;
    };
  }
  hookHistory('pushState');
  hookHistory('replaceState');
  window.addEventListener('popstate', function () { enforceLocation(); schedule(); });
  enforceLocation();

  // ---- Hiding ------------------------------------------------------------
  function flag(element, category) {
    if (!element) { return; }
    var current = element.getAttribute(HIDDEN_ATTR) || '';
    if ((' ' + current + ' ').indexOf(' ' + category + ' ') >= 0) { return; }
    element.setAttribute(HIDDEN_ATTR, (current + ' ' + category).trim());
  }

  // Climb from a node inside the feed to the block that sits beside the feed's articles
  // (or beside other top-level feed blocks), which is the unit Instagram inserts and removes.
  function feedBlock(node) {
    var current = node;
    for (var i = 0; i < MAX_CLIMB && current && current.parentElement; i++) {
      var parent = current.parentElement;
      if (parent.tagName === 'MAIN' || parent.tagName === 'SECTION' || parent.querySelector(':scope > article')) {
        return current;
      }
      current = parent;
    }
    return node.closest('article') || node;
  }

  function leafText(element) {
    if (element.children.length > 0) { return null; }
    var text = element.textContent;
    return text ? text.trim() : '';
  }

  var LABELS = [
    { category: 'ads', match: function (t) { return t === 'Sponsored' || t === 'Paid partnership'; } },
    { category: 'suggested', match: function (t) { return /^Suggested (for you|posts|accounts|reels)$/i.test(t) || t === 'Suggestions for you'; } },
    { category: 'reels', match: function (t) { return t === 'Reels' || t === 'Suggested reels'; } }
  ];

  function scanFeedLabels() {
    var main = document.querySelector('main');
    if (!main) { return; }
    var onHome = location.pathname === '/';
    var leaves = main.querySelectorAll('span, div, h1, h2, h3, h4, a');
    for (var i = 0; i < leaves.length; i++) {
      var text = leafText(leaves[i]);
      if (text === null || text.length === 0 || text.length > 24) { continue; }
      if (leaves[i].closest('nav, [role="navigation"]')) { continue; }
      for (var j = 0; j < LABELS.length; j++) {
        if (LABELS[j].category === 'reels' && !onHome) { continue; }
        if (LABELS[j].match(text)) {
          flag(feedBlock(leaves[i]), LABELS[j].category);
          break;
        }
      }
    }
  }

  function scanReelsRail() {
    var links = document.querySelectorAll('main a[href="/reels/"]');
    for (var i = 0; i < links.length; i++) {
      if (links[i].closest('nav, [role="navigation"]')) { continue; }
      flag(feedBlock(links[i]), 'reels');
    }
  }

  function scanStoriesTray() {
    var main = document.querySelector('main');
    if (!main) { return; }
    var links = main.querySelectorAll('a[href^="/stories/"]:not([href^="/stories/highlights/"])');
    if (links.length < 2) { return; }
    var block = feedBlock(links[0]);
    if (block && block.querySelectorAll('a[href^="/stories/"]').length >= 2) {
      flag(block, 'stories');
    }
  }

  // ---- Feed selector -----------------------------------------------------
  function enforceFeedHeader() {
    if (location.pathname !== '/' || window !== window.top) { return; }
    var header = document.querySelector('header') || document.querySelector('main');
    if (!header) { return; }
    var leaves = header.querySelectorAll('span, div, h1, h2');
    for (var i = 0; i < leaves.length; i++) {
      var text = leafText(leaves[i]);
      if (text === 'For you') {
        location.replace(homePath());
        return;
      }
    }
    var chevrons = document.querySelectorAll('header svg[aria-label="Down chevron icon"], header svg[aria-label="Down Chevron Icon"]');
    for (var k = 0; k < chevrons.length; k++) {
      var button = chevrons[k].closest('[role="button"], button');
      if (button) { button.style.pointerEvents = 'none'; }
    }
  }

  // ---- Hand-off for media the web client cannot show ----------------------
  var HANDOFF_RE = /can only be (replayed|viewed|seen) once|use the (mobile |instagram )?app to (view|listen|see)|not available on (the )?web|open the instagram app/i;

  function postOpenInApp() {
    try {
      window.webkit.messageHandlers.feedless.postMessage({ type: 'openInApp', url: location.href });
    } catch (error) {
      // Not running inside the Feedless web view.
    }
  }

  function scanHandoffPlaceholders() {
    if (location.pathname.indexOf('/direct/') !== 0) { return; }
    var main = document.querySelector('main') || document.body;
    if (!main) { return; }
    var leaves = main.querySelectorAll('span, div, p');
    for (var i = 0; i < leaves.length; i++) {
      var text = leafText(leaves[i]);
      if (!text || text.length > 160 || !HANDOFF_RE.test(text)) { continue; }
      var container = leaves[i].parentElement || leaves[i];
      if (container.querySelector('.feedless-handoff')) { continue; }
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'feedless-handoff';
      button.textContent = 'Open in Instagram app';
      button.addEventListener('click', function (event) {
        event.preventDefault();
        event.stopPropagation();
        postOpenInApp();
      });
      leaves[i].insertAdjacentElement('afterend', button);
    }
  }

  // ---- Scheduling --------------------------------------------------------
  function run() {
    scheduled = null;
    if (!document.body) { return; }
    try {
      enforceFeedHeader();
      if (enabled('ads') || enabled('suggested') || enabled('reels')) { scanFeedLabels(); }
      if (enabled('reels')) { scanReelsRail(); }
      if (enabled('stories')) { scanStoriesTray(); }
      scanHandoffPlaceholders();
    } catch (error) {
      // A selector that no longer matches must never break the page.
    }
  }

  function schedule() {
    if (scheduled !== null) { return; }
    scheduled = setTimeout(run, DEBOUNCE_MS);
  }

  function start() {
    run();
    var observer = new MutationObserver(schedule);
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }

  // Called by the native side after a settings change; attributes are flipped by the caller.
  window.__feedlessApply = function (next) {
    config = next || config;
    enforceLocation();
    schedule();
  };
})();
