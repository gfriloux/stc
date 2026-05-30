/* ============================================================================
   STC · stc-fx.js  — client-side grimdark effects for the Starlight docs
   ----------------------------------------------------------------------------
   Place at docs/public/stc-fx.js and load via the `head` array in
   astro.config.mjs (see snippet). Pure vanilla, no deps.

   Provides:
     · CRT scanline + metal-grain overlays (respect the effect dials)
     · "Console Cogitator" — a floating panel to toggle scanlines / grain /
       glow / animations at runtime (persisted in localStorage). Theme (dark/
       light) is intentionally NOT here — Starlight's own header toggle owns it.
     · Hero decrypt-typing for .stc-hero-tagline[data-typed]
     · Scroll-reveal: added by JS only, so content is never hidden without JS.
   ========================================================================= */
(function () {
  "use strict";
  if (window.__stcFx) return; window.__stcFx = true;

  var root = document.documentElement;
  var reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  var KEY = "stc-fx";
  var fx = loadFx();

  function loadFx() {
    var d = { scan: true, grain: true, glow: 1, anim: !reduce };
    try { return Object.assign(d, JSON.parse(localStorage.getItem(KEY) || "{}")); }
    catch (e) { return d; }
  }
  function saveFx() { try { localStorage.setItem(KEY, JSON.stringify(fx)); } catch (e) {} }
  function applyFx() {
    root.style.setProperty("--stc-scanline-opacity", fx.scan ? "" : "0");
    root.style.setProperty("--stc-grain-opacity", fx.grain ? "" : "0");
    root.style.setProperty("--stc-glow-strength", String(fx.glow));
    root.style.setProperty("--stc-anim", fx.anim ? "1" : "0.0001");
  }

  document.addEventListener("DOMContentLoaded", init);
  if (document.readyState !== "loading") init();

  var booted = false;
  function init() {
    if (booted) return; booted = true;
    applyFx();
    injectOverlays();
    injectConsole();
    runType();
    armReveal();
  }

  /* ---- overlays ---- */
  function injectOverlays() {
    ["stc-scanlines", "stc-grain"].forEach(function (c) {
      if (document.querySelector("." + c)) return;
      var d = document.createElement("div"); d.className = c; document.body.appendChild(d);
    });
  }

  /* ---- cogitator console ---- */
  function injectConsole() {
    if (document.getElementById("stc-console-toggle")) return;
    var css = document.createElement("style");
    css.textContent = CONSOLE_CSS;
    document.head.appendChild(css);

    var btn = document.createElement("button");
    btn.id = "stc-console-toggle"; btn.type = "button";
    btn.setAttribute("aria-label", "Console Cogitator");
    btn.innerHTML = GEAR_SVG;
    document.body.appendChild(btn);

    var panel = document.createElement("div");
    panel.id = "stc-console"; panel.hidden = true;
    panel.innerHTML =
      '<div class="stc-console-head">Console Cogitator <span class="led"></span></div>' +
      '<div class="stc-console-body">' +
        field("Scanlines CRT", toggle("scan", fx.scan)) +
        field("Grain métallique", toggle("grain", fx.grain)) +
        '<div class="stc-field"><div class="stc-field-label">Lueur sacrée <span class="val" id="stc-glow-val">' +
          Math.round(fx.glow * 100) + '%</span></div>' +
          '<input class="stc-range" type="range" min="0" max="2" step="0.25" value="' + fx.glow + '" data-range="glow"></div>' +
        field("Animations", toggle("anim", fx.anim)) +
      "</div>";
    document.body.appendChild(panel);

    btn.addEventListener("click", function () { panel.hidden = !panel.hidden; });
    document.addEventListener("click", function (e) {
      if (!panel.hidden && !panel.contains(e.target) && !btn.contains(e.target)) panel.hidden = true;
    });
    panel.querySelectorAll("[data-toggle]").forEach(function (t) {
      t.addEventListener("click", function () {
        t.classList.toggle("is-on");
        fx[t.dataset.toggle] = t.classList.contains("is-on");
        applyFx(); saveFx();
      });
    });
    var range = panel.querySelector('[data-range="glow"]');
    range.addEventListener("input", function () {
      fx.glow = parseFloat(range.value);
      document.getElementById("stc-glow-val").textContent = Math.round(fx.glow * 100) + "%";
      applyFx(); saveFx();
    });

    function field(label, control) {
      return '<div class="stc-field"><div class="stc-field-label">' + label + "</div>" + control + "</div>";
    }
    function toggle(key, on) {
      return '<div class="stc-toggle' + (on ? " is-on" : "") + '" data-toggle="' + key + '" role="switch"></div>';
    }
  }

  /* ---- hero decrypt-typing ---- */
  var GLYPHS = "▚▞█▓▒░#@%&/\\<>=+*";
  function runType() {
    var el = document.querySelector(".stc-hero-tagline[data-typed]");
    if (!el) return;
    var full = el.getAttribute("data-typed") || "";
    if (!fx.anim || reduce) { el.innerHTML = esc(full) + '<span class="stc-caret"></span>'; return; }
    var i = 0;
    var timer = setInterval(function () {
      i++;
      if (i > full.length) { clearInterval(timer); el.innerHTML = esc(full) + '<span class="stc-caret"></span>'; return; }
      var scr = "";
      for (var k = i; k < Math.min(full.length, i + 5); k++) {
        scr += (full[k] === "\n" || full[k] === " ") ? full[k] : GLYPHS[(Math.random() * GLYPHS.length) | 0];
      }
      el.innerHTML = esc(full.slice(0, i)) +
        '<span style="color:var(--stc-brass)">' + esc(scr) + '</span><span class="stc-caret"></span>';
    }, 28);
  }
  function esc(s) { return s.replace(/[&<>]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]; }); }

  /* ---- scroll reveal (JS-added so no-JS keeps content visible) ---- */
  function armReveal() {
    if (reduce) return;
    var targets = document.querySelectorAll(
      ".stc-hero-inner > *, .sl-markdown-content .card, .sl-markdown-content > h2"
    );
    if (!targets.length || !("IntersectionObserver" in window)) return;
    var io = new IntersectionObserver(function (ents) {
      ents.forEach(function (en) { if (en.isIntersecting) { en.target.classList.add("is-in"); io.unobserve(en.target); } });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    targets.forEach(function (el, idx) {
      el.classList.add("stc-reveal");
      el.style.animationDelay = (idx % 4 * 0.07) + "s";
      io.observe(el);
    });
  }

  /* ---- assets ---- */
  var GEAR_SVG =
    '<svg viewBox="0 0 100 100" width="26" height="26" aria-hidden="true">' +
    '<path d="M52.79,10.10 L56.95,3.52 L63.91,5.11 L64.80,12.84 L69.83,15.26 L76.43,11.13 L82.01,15.59 L79.46,22.94 L82.94,27.30 L90.67,26.45 L93.77,32.88 L88.28,38.40 L89.52,43.84 L96.86,46.43 L96.86,53.57 L89.52,56.16 L88.28,61.60 L93.77,67.12 L90.67,73.55 L82.94,72.70 L79.46,77.06 L82.01,84.41 L76.43,88.87 L69.83,84.74 L64.80,87.16 L63.91,94.89 L56.95,96.48 L52.79,89.90 L47.21,89.90 L43.05,96.48 L36.09,94.89 L35.20,87.16 L30.17,84.74 L23.57,88.87 L17.99,84.41 L20.54,77.06 L17.06,72.70 L9.33,73.55 L6.23,67.12 L11.72,61.60 L10.48,56.16 L3.14,53.57 L3.14,46.43 L10.48,43.84 L11.72,38.40 L6.23,32.88 L9.33,26.45 L17.06,27.30 L20.54,22.94 L17.99,15.59 L23.57,11.13 L30.17,15.26 L35.20,12.84 L36.09,5.11 L43.05,3.52 L47.21,10.10 Z" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/>' +
    '<circle cx="50" cy="50" r="33.5" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>';

  var CONSOLE_CSS =
    '#stc-console-toggle{position:fixed;right:22px;bottom:22px;z-index:9995;width:50px;height:50px;display:grid;place-items:center;cursor:pointer;color:var(--stc-brass);background:linear-gradient(var(--stc-bg-3),var(--stc-bg-inset));border:1px solid var(--stc-brass-deep);box-shadow:0 8px 24px -8px #000,0 0 calc(16px*var(--stc-glow-strength)) color-mix(in oklab,var(--stc-red) 30%,transparent)}' +
    '#stc-console-toggle svg{animation:stc-spin 22s linear infinite}' +
    '#stc-console-toggle:hover{color:var(--stc-red-bright);border-color:var(--stc-red)}' +
    '#stc-console{position:fixed;right:22px;bottom:84px;z-index:9996;width:288px;background:linear-gradient(var(--stc-bg-2),var(--stc-bg));border:1px solid var(--stc-line-2);box-shadow:0 30px 60px -20px #000,inset 0 0 0 1px #000;font-family:var(--stc-font-body)}' +
    '#stc-console[hidden]{display:none}' +
    '.stc-console-head{display:flex;align-items:center;gap:9px;padding:13px 16px;border-bottom:1px solid var(--stc-red);font-family:var(--stc-font-display);font-weight:700;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--stc-brass)}' +
    '.stc-console-head .led{width:7px;height:7px;border-radius:50%;background:var(--stc-red-bright);box-shadow:0 0 8px var(--stc-red-glow);animation:stc-blink 1.6s steps(1) infinite;margin-left:auto}' +
    '.stc-console-body{padding:6px 16px 16px}' +
    '.stc-field{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:11px 0;border-bottom:1px solid var(--stc-line)}' +
    '.stc-field:last-child{border-bottom:none}.stc-field>.stc-field-label:only-child,.stc-field-label{font-family:var(--stc-font-mono);font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;color:var(--stc-text-dim);display:flex;align-items:center;gap:8px}' +
    '.stc-field-label .val{color:var(--stc-brass)}' +
    '.stc-field:has(.stc-range){display:block}.stc-field:has(.stc-range) .stc-field-label{justify-content:space-between;margin-bottom:9px}' +
    '.stc-range{width:100%;appearance:none;-webkit-appearance:none;height:3px;background:var(--stc-line-2);cursor:pointer}' +
    '.stc-range::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;transform:rotate(45deg);background:var(--stc-red-bright);box-shadow:0 0 8px var(--stc-red-glow)}' +
    '.stc-toggle{width:42px;height:22px;flex:none;border:1px solid var(--stc-line-2);background:var(--stc-bg-inset);cursor:pointer;position:relative;transition:.18s}' +
    '.stc-toggle::after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;background:var(--stc-text-faint);transition:.18s}' +
    '.stc-toggle.is-on{border-color:var(--stc-red);background:color-mix(in oklab,var(--stc-red) 30%,transparent)}' +
    '.stc-toggle.is-on::after{left:22px;background:var(--stc-red-bright);box-shadow:0 0 8px var(--stc-red-glow)}' +
    '@media (prefers-reduced-motion: reduce){#stc-console-toggle svg{animation:none}}';
})();
