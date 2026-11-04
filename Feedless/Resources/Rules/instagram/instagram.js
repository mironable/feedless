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

  // ---- Network log (debug) ----------------------------------------------
  var NET_MAX = 300;
  var net = window.__feedlessNet = [];

  function headersToObject(headers) {
    var out = {};
    try {
      if (!headers) { return out; }
      if (typeof headers.forEach === 'function') {
        headers.forEach(function (value, key) { out[key] = value; });
      } else {
        Object.keys(headers).forEach(function (key) { out[key] = headers[key]; });
      }
    } catch (error) { /* ignore */ }
    return out;
  }

  function bodyToString(body) {
    try {
      if (body == null) { return null; }
      if (typeof body === 'string') { return body.slice(0, 4000); }
      if (body instanceof URLSearchParams) { return body.toString().slice(0, 4000); }
      if (body instanceof FormData) {
        var parts = [];
        body.forEach(function (value, key) { parts.push(key + '=' + String(value).slice(0, 300)); });
        return parts.join('&').slice(0, 4000);
      }
      return '[' + (body.constructor && body.constructor.name) + ']';
    } catch (error) { return null; }
  }

  function record(entry) {
    if (net.length >= NET_MAX) { net.shift(); }
    net.push(entry);
  }

  // The DM badge comes from a GraphQL query the page repeats on its own. Keeping the last
  // one lets the native side replay it in the background with the same tokens.
  function isBadgeRequest(entry) {
    if (entry.url.indexOf('/api/graphql') < 0) { return false; }
    var name = (entry.headers && (entry.headers['X-FB-Friendly-Name'] || entry.headers['x-fb-friendly-name'])) || '';
    return /BadgeCount/i.test(name) || /fb_api_req_friendly_name=[^&]*BadgeCount/i.test(entry.body || '');
  }

  function keepBadgeRequest(entry, responseText) {
    if (!isBadgeRequest(entry)) { return; }
    entry.response = responseText ? String(responseText).slice(0, 60000) : null;
    window.__feedlessBadgeRequest = {
      t: entry.t,
      url: entry.url,
      headers: entry.headers,
      body: entry.body,
      response: entry.response
    };
  }

  window.addEventListener('error', function (event) {
    record({ t: Date.now(), kind: 'error', message: String(event.message), source: String(event.filename) + ':' + event.lineno });
  });
  window.addEventListener('unhandledrejection', function (event) {
    var reason = event.reason;
    record({ t: Date.now(), kind: 'rejection', message: String(reason && reason.message ? reason.message : reason), stack: String(reason && reason.stack ? reason.stack : '').slice(0, 600) });
  });

  if (window.fetch) {
    var originalFetch = window.fetch;
    window.fetch = function (input, init) {
      var entry = {
        t: Date.now(),
        kind: 'fetch',
        method: (init && init.method) || (input && input.method) || 'GET',
        url: String(input && input.url ? input.url : input),
        headers: headersToObject(init && init.headers ? init.headers : (input && input.headers)),
        body: bodyToString(init && init.body),
        status: null
      };
      record(entry);
      return originalFetch.apply(this, arguments).then(function (response) {
        entry.status = response.status;
        if (isBadgeRequest(entry)) {
          response.clone().text().then(function (text) { keepBadgeRequest(entry, text); }, function () {});
        }
        return response;
      }, function (error) {
        entry.status = 'error';
        throw error;
      });
    };
  }

  if (window.XMLHttpRequest) {
    var open = XMLHttpRequest.prototype.open;
    var send = XMLHttpRequest.prototype.send;
    var setHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__fl = { t: Date.now(), kind: 'xhr', method: method, url: String(url), headers: {}, body: null, status: null };
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.setRequestHeader = function (key, value) {
      if (this.__fl) { this.__fl.headers[key] = value; }
      return setHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function (body) {
      var entry = this.__fl;
      if (entry) {
        entry.body = bodyToString(body);
        record(entry);
        this.addEventListener('loadend', function () {
          entry.status = this.status;
          try { keepBadgeRequest(entry, this.responseType === '' || this.responseType === 'text' ? this.responseText : null); } catch (error) { /* ignore */ }
        });
      }
      return send.apply(this, arguments);
    };
  }

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
  function enforceLocation(viaHistory) {
    setPathAttribute();
    if (window !== window.top) { return; }
    var path = location.pathname;
    if (path.indexOf('/reels/') === 0) {
      location.replace(homePath());
      return;
    }
    if ((path === '/' || path === '') && !viaHistory && !hasFeedVariant()) {
      // A real page load without a feed variant; in-page hops are handled by enforceFeedVariant.
      location.replace(homePath());
    }
  }

  function hasFeedVariant() {
    return FEED_VARIANTS.indexOf(new URLSearchParams(location.search).get('variant')) >= 0;
  }

  function hookHistory(method) {
    var original = history[method];
    history[method] = function () {
      var result = original.apply(this, arguments);
      enforceLocation(true);
      schedule();
      return result;
    };
  }
  hookHistory('pushState');
  hookHistory('replaceState');
  window.addEventListener('popstate', function () { enforceLocation(true); schedule(); });
  enforceLocation(false);

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

  function rewriteHomeLinks() {
    var links = document.querySelectorAll('a[href="/"]');
    for (var i = 0; i < links.length; i++) {
      links[i].setAttribute('href', homePath());
    }
  }

  // ---- Feed selector -----------------------------------------------------
  // Instagram's router drops the variant when it navigates to the default feed, so the URL
  // says which feed rendered without reading localised header text. Recovery goes through
  // Instagram's own router via the rewritten home link; a full reload is the fallback.
  var RECOVERY_SETTLE_MS = 800;
  var RECOVERY_MAX_CLICKS = 2;
  var variantMissingSince = 0;
  var recoveryClicks = 0;
  var recoveryReloaded = false;

  function enforceFeedVariant() {
    if (location.pathname !== '/' || window !== window.top) { return; }
    if (hasFeedVariant()) {
      variantMissingSince = 0;
      recoveryClicks = 0;
      return;
    }
    var now = Date.now();
    if (!variantMissingSince) {
      variantMissingSince = now;
      setTimeout(schedule, RECOVERY_SETTLE_MS);
      return;
    }
    if (now - variantMissingSince < RECOVERY_SETTLE_MS) { return; }
    var link = document.querySelector('a[href="' + homePath() + '"]');
    if (link && recoveryClicks < RECOVERY_MAX_CLICKS) {
      recoveryClicks += 1;
      variantMissingSince = now;
      record({ t: now, kind: 'feedless', message: 'feed recovery click ' + recoveryClicks });
      link.click();
      setTimeout(schedule, RECOVERY_SETTLE_MS * 2);
      return;
    }
    if (!recoveryReloaded) {
      recoveryReloaded = true;
      record({ t: now, kind: 'feedless', message: 'feed recovery reload' });
      location.replace(homePath());
      return;
    }
    var chevrons = document.querySelectorAll('header svg[aria-label="Down chevron icon"], header svg[aria-label="Down Chevron Icon"]');
    for (var k = 0; k < chevrons.length; k++) {
      var button = chevrons[k].closest('[role="button"], button');
      if (button) { button.style.pointerEvents = 'none'; }
    }
  }

  // ---- Settings entry in Instagram's header ---------------------------------
  // The home header's right-hand row is [new post] [notifications]. A clone of the new-post
  // cell carries Instagram's own sizing; only the icon and the click differ.
  var GEAR_SVG = '<circle cx="12" cy="12" r="3.25" fill="none" stroke="currentColor" stroke-width="2"/>' +
    '<path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M12 2.5v2.4M12 19.1v2.4M2.5 12h2.4M19.1 12h2.4M5.3 5.3l1.7 1.7M17 17l1.7 1.7M5.3 18.7 7 17M17 7l1.7-1.7"/>' +
    '<circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="2"/>';

  function postMessage(body) {
    try {
      window.webkit.messageHandlers.feedless.postMessage(body);
    } catch (error) {
      // Not running inside the Feedless web view.
    }
  }

  function commonAncestor(a, b) {
    var node = a;
    while (node && !node.contains(b)) { node = node.parentElement; }
    return node;
  }

  // The ancestor of `node` that is a direct child of `group`.
  function childOf(group, node) {
    var current = node;
    while (current && current.parentElement !== group) { current = current.parentElement; }
    return current;
  }

  function injectSettingsButton() {
    if (window !== window.top || document.getElementById('feedless-settings')) { return; }
    var header = document.querySelector('header');
    if (!header) { return; }
    var plus = header.querySelector('a[href="#"]');
    var heart = header.querySelector('a[href="/notifications/"]');
    if (!plus || !heart || !plus.querySelector('svg')) { return; }
    var group = commonAncestor(plus, heart);
    var plusCell = childOf(group, plus);
    if (!group || !plusCell) { return; }
    var clone = plusCell.cloneNode(true);
    var forms = clone.querySelectorAll('form, input');
    for (var i = 0; i < forms.length; i++) { forms[i].remove(); }
    var described = clone.querySelectorAll('[aria-describedby]');
    for (var j = 0; j < described.length; j++) { described[j].removeAttribute('aria-describedby'); }
    var link = clone.querySelector('a');
    var svg = clone.querySelector('svg');
    if (!link || !svg) { return; }
    link.id = 'feedless-settings';
    link.setAttribute('href', '#');
    link.setAttribute('aria-label', 'Feedless settings');
    svg.setAttribute('aria-label', 'Feedless settings');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.innerHTML = '<title>Feedless settings</title>' + GEAR_SVG;
    var lastOpen = 0;
    function open(event) {
      event.preventDefault();
      event.stopPropagation();
      if (Date.now() - lastOpen < 600) { return; }
      lastOpen = Date.now();
      postMessage({ type: 'openSettings' });
    }
    link.addEventListener('touchend', open, true);
    link.addEventListener('click', open, true);
    group.insertBefore(clone, plusCell);
    html.setAttribute('data-fl-gear', '');
  }

  // ---- Bottom nav ---------------------------------------------------------
  // Hiding only the <a> leaves its wrapper in the flex row and the spacing uneven.
  // Flag the whole cell, found as the link's ancestor beside the Home cell.
  var NAV_CELLS = [
    { category: 'reels', selector: 'a[href="/reels/"]' },
    { category: 'explore', selector: 'a[href="/explore/"]' }
  ];

  function flagNavCells() {
    var home = document.querySelector('a[href="' + homePath() + '"], a[href="/"]');
    if (!home) { return; }
    for (var i = 0; i < NAV_CELLS.length; i++) {
      var links = document.querySelectorAll(NAV_CELLS[i].selector);
      for (var j = 0; j < links.length; j++) {
        if (links[j].closest('header')) { continue; }
        var group = commonAncestor(links[j], home);
        var cell = group ? childOf(group, links[j]) : null;
        flag(cell || links[j], NAV_CELLS[i].category);
      }
    }
  }

  // ---- Hand-off for media the web client cannot show ----------------------
  var HANDOFF_RE = /can only be (replayed|viewed|seen) once|use the (mobile |instagram )?app to (view|listen|see)|not available on (the )?web|open the instagram app/i;

  function postOpenInApp() {
    postMessage({ type: 'openInApp', url: location.href });
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
      rewriteHomeLinks();
      enforceFeedVariant();
      injectSettingsButton();
      flagNavCells();
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

  new MutationObserver(function () {
    if (!document.getElementById('feedless-settings')) { injectSettingsButton(); }
    schedule();
  }).observe(document.documentElement, { childList: true, subtree: true });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run, { once: true });
  } else {
    run();
  }

  // Called by the native side after a settings change; attributes are flipped by the caller.
  window.__feedlessApply = function (next) {
    config = next || config;
    enforceLocation(true);
    schedule();
  };
})();
