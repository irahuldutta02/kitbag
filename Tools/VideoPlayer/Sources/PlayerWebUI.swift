import Foundation

/// Self-contained Apple Liquid Glass web player served locally on 127.0.0.1.
/// Zero external CDN requests — works 100% offline with instant load.
enum PlayerWebUI {
  static let faviconSVG: String = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#ff6b3d"/>
      <stop offset="52%" stop-color="#ff4757"/>
      <stop offset="100%" stop-color="#c42b6c"/>
    </linearGradient>
    <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.34"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="6" y="6" width="116" height="116" rx="28" fill="url(#g)"/>
  <rect x="6" y="6" width="116" height="58" rx="28" fill="url(#shine)"/>
  <path d="M50 40.5c0-3.4 3.7-5.5 6.6-3.7l35.4 22.5c2.7 1.7 2.7 5.7 0 7.4L56.6 89.2c-2.9 1.8-6.6-.3-6.6-3.7V40.5z" fill="#fff"/>
</svg>
"""#

  static let html: String = #"""
<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kitbag Video Player</title>
<meta name="theme-color" content="#0d0d0f">
<link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">
<style>
  :root {
    --font: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif;
    --mono: ui-monospace, "SF Mono", Menlo, monospace;
    --ease: cubic-bezier(0.22, 1, 0.36, 1);

    --acc: #ff5a36;
    --acc2: #ff8a3d;
    --acc-glow: rgba(255, 90, 54, 0.34);
    --blue: #0a84ff;
    --danger: #ff453a;

    --ga: 0.11;
    --gb: 28px;
    --gt: 0;
    --dim: 0.42;
    --bgi: url(/api/wallpaper);
    --sub-scale: 1;
  }

  html[data-theme="dark"] {
    color-scheme: dark;
    --bg: #0b0b0e;
    --fg: #f5f5f7;
    --mut: rgba(235, 235, 245, 0.62);
    --dim-text: rgba(235, 235, 245, 0.42);
    --glass-fill: rgba(255, 255, 255, var(--ga));
    --glass-hi: rgba(255, 255, 255, calc(var(--ga) + 0.085));
    --glass-line: rgba(255, 255, 255, 0.18);
    --glass-line-soft: rgba(255, 255, 255, 0.09);
    --glass-bg: linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0)), linear-gradient(rgba(12,12,16,var(--gt)), rgba(12,12,16,var(--gt))), rgba(28, 28, 34, calc(0.22 + var(--ga)));
    --glass-pop: rgba(26, 26, 32, 0.78);
    --glass-sh: inset 0 1px 0 rgba(255,255,255,0.28), inset 0 -1px 0 rgba(255,255,255,0.05), 0 14px 40px rgba(0,0,0,0.42);
    --input-bg: rgba(0, 0, 0, 0.32);
    --row-hover: rgba(255, 255, 255, 0.085);
    --scrim: rgba(8, 8, 12, var(--dim));
    --modal-scrim: rgba(6, 6, 10, 0.56);
    --opt-bg: #1c1c20;
    --kbd-bg: rgba(255,255,255,0.1);
  }

  html[data-theme="light"] {
    color-scheme: light;
    --bg: #eef0f4;
    --fg: #1d1d1f;
    --mut: rgba(29, 29, 31, 0.62);
    --dim-text: rgba(29, 29, 31, 0.42);
    --glass-fill: rgba(255, 255, 255, calc(0.36 + var(--ga)));
    --glass-hi: rgba(255, 255, 255, calc(0.55 + var(--ga)));
    --glass-line: rgba(255, 255, 255, 0.65);
    --glass-line-soft: rgba(0, 0, 0, 0.08);
    --glass-bg: linear-gradient(180deg, rgba(255,255,255,0.45), rgba(255,255,255,0.12)), linear-gradient(rgba(235,238,245,var(--gt)), rgba(235,238,245,var(--gt))), rgba(255, 255, 255, calc(0.46 + var(--ga)));
    --glass-pop: rgba(248, 248, 252, 0.86);
    --glass-sh: inset 0 1px 0 rgba(255,255,255,0.85), inset 0 -1px 0 rgba(0,0,0,0.04), 0 14px 36px rgba(0,0,0,0.14);
    --input-bg: rgba(255, 255, 255, 0.52);
    --row-hover: rgba(0, 0, 0, 0.055);
    --scrim: rgba(242, 244, 248, calc(var(--dim) * 0.85));
    --modal-scrim: rgba(20, 22, 30, 0.34);
    --opt-bg: #f5f5f7;
    --kbd-bg: rgba(0,0,0,0.07);
  }

  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { height: 100%; }
  body {
    margin: 0;
    font: 14px/1.42 var(--font);
    background: var(--bg);
    color: var(--fg);
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
  }
  button, select, input { font: inherit; color: inherit; }
  button { cursor: pointer; border: 0; }
  svg { width: 18px; height: 18px; fill: currentColor; display: block; flex: none; }
  [hidden] { display: none !important; }

  .glass {
    background: var(--glass-bg);
    border: 1px solid var(--glass-line);
    box-shadow: var(--glass-sh);
    -webkit-backdrop-filter: blur(var(--gb)) saturate(190%);
    backdrop-filter: blur(var(--gb)) saturate(190%);
  }

  /* ==================== LIBRARY ==================== */
  #lib {
    position: relative;
    height: 100%;
    overflow: hidden;
    background-color: var(--bg);
    background-repeat: no-repeat;
    background-position: center;
    background-image:
      radial-gradient(960px 560px at 8% -12%, rgba(255, 90, 54, 0.16), transparent 60%),
      radial-gradient(820px 520px at 96% 8%, rgba(10, 132, 255, 0.14), transparent 58%),
      linear-gradient(var(--scrim), var(--scrim)),
      var(--bgi);
    background-size: auto, auto, auto, cover;
  }

  .main {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    max-width: 900px;
    margin: 0 auto;
    padding: 26px 24px 20px;
    gap: 12px;
  }

  /* Top brand + quick locations header */
  .hero {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 4px;
  }
  .app-badge {
    width: 38px;
    height: 38px;
    border-radius: 11px;
    overflow: hidden;
    box-shadow: 0 6px 18px var(--acc-glow);
    flex: none;
  }
  .app-badge img { width: 100%; height: 100%; display: block; }
  .hero-title { display: flex; flex-direction: column; min-width: 0; }
  .hero-title h1 {
    margin: 0;
    font-size: 19px;
    font-weight: 700;
    letter-spacing: -0.024em;
    line-height: 1.15;
  }
  .hero-title span {
    font-size: 12px;
    color: var(--mut);
    font-weight: 500;
  }
  .hero-sp { flex: 1; }
  .quick-pills {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
    justify-content: flex-end;
  }
  .pill-btn {
    padding: 6px 12px;
    border-radius: 999px;
    font-size: 12.5px;
    font-weight: 600;
    background: var(--glass-fill);
    border: 1px solid var(--glass-line-soft);
    color: var(--mut);
    -webkit-backdrop-filter: blur(18px);
    backdrop-filter: blur(18px);
    transition: background 0.15s, color 0.15s, transform 0.12s;
  }
  .pill-btn:hover { background: var(--glass-hi); color: var(--fg); }
  .pill-btn.active { background: var(--glass-hi); color: var(--fg); border-color: var(--glass-line); }
  .pill-btn:active { transform: scale(0.96); }

  .view-toggle { display: inline-flex; gap: 2px; padding: 3px; border-radius: 11px; background: var(--glass-line-soft); flex: none; }
  .view-toggle button { width: 30px; height: 28px; border: 0; border-radius: 8px; background: transparent; color: var(--mut); display: grid; place-items: center; cursor: pointer; }
  .view-toggle button svg { width: 15px; height: 15px; }
  .view-toggle button.active { background: var(--glass-hi); color: var(--fg); }
  .view-toggle button:hover { color: var(--fg); }

  /* Continue Watching rail */
  #recentsWrap {
    display: flex;
    flex-direction: column;
    gap: 7px;
  }
  .sec-label {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--mut);
    padding-left: 6px;
  }
  .recents {
    display: flex;
    gap: 10px;
    overflow-x: auto;
    padding: 2px 2px 4px;
    scrollbar-width: none;
  }
  .recents::-webkit-scrollbar { display: none; }
  .rcard {
    flex: 0 0 220px;
    width: 220px; min-width: 0; max-width: 220px; box-sizing: border-box; overflow: hidden;
    padding: 7px 7px 11px;
    border-radius: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    text-align: left;
    transition: transform 0.18s var(--ease), background 0.15s;
  }
  .rcard:hover { transform: translateY(-2px); background: var(--glass-hi); }
  .rcard:active { transform: scale(0.98); }
  .rcard-ic {
    position: relative; width: 100%; aspect-ratio: 16 / 9; border-radius: 10px; flex: none;
    background: linear-gradient(135deg, rgba(255,90,54,0.55), rgba(255,138,61,0.35));
    color: #fff; display: grid; place-items: center;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08);
  }
  .rcard-ic svg { width: 22px; height: 22px; }
  .rcard-body { padding: 0 4px; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .rcard-nm {
    font-size: 13px; font-weight: 600;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .rcard-sub { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 11.5px; color: var(--mut); font-variant-numeric: tabular-nums; }
  .rcard .prog-track { margin: 0 4px; }
  .prog-track {
    height: 4px; border-radius: 99px;
    background: var(--glass-line-soft); overflow: hidden;
  }
  .prog-fill {
    height: 100%; border-radius: 99px;
    background: linear-gradient(90deg, var(--acc), var(--acc2));
  }

  /* Toolbar card */
  .tools {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 11px 12px;
    border-radius: 22px;
  }
  .toolbar { display: flex; align-items: center; gap: 8px; }
  .btn {
    padding: 8px 15px;
    border-radius: 999px;
    background: var(--glass-fill);
    border: 1px solid var(--glass-line);
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.22);
    font-weight: 600;
    font-size: 13.5px;
    transition: background 0.15s, transform 0.12s, filter 0.15s;
    white-space: nowrap;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
  }
  .btn:hover { background: var(--glass-hi); }
  .btn:active { transform: scale(0.96); }
  .btn:disabled { opacity: 0.35; cursor: default; transform: none; }
  .btn.nav { width: 36px; height: 36px; padding: 0; flex: none; }
  .btn.primary {
    background: linear-gradient(135deg, var(--acc), var(--acc2));
    border-color: transparent;
    color: #fff;
    text-shadow: 0 1px 2px rgba(0,0,0,0.2);
    box-shadow: 0 4px 16px var(--acc-glow);
  }
  .btn.primary:hover { filter: brightness(1.08); }

  .field {
    flex: 1;
    min-width: 0;
    padding: 8px 14px;
    border-radius: 999px;
    background: var(--input-bg);
    border: 1px solid var(--glass-line-soft);
    outline: 0;
    font-size: 13.5px;
    transition: border-color 0.15s, box-shadow 0.15s;
  }
  .field:focus {
    border-color: var(--acc2);
    box-shadow: 0 0 0 3px rgba(255, 90, 54, 0.22);
  }
  .subbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 4px;
  }
  .crumbs {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 1px;
    align-items: center;
    color: var(--mut);
    font-size: 12.5px;
  }
  .crumbs button {
    background: none;
    color: var(--mut);
    padding: 2px 6px;
    border-radius: 6px;
    font-weight: 500;
  }
  .crumbs button:hover { background: var(--row-hover); color: var(--fg); }
  .crumbs span { opacity: 0.42; font-size: 12px; }
  .filter-wrap {
    position: relative;
    width: 190px;
    flex: none;
  }
  .filter-wrap svg {
    position: absolute; left: 10px; top: 50%; transform: translateY(-50%);
    width: 13px; height: 13px; color: var(--dim-text); pointer-events: none;
  }
  #filter {
    width: 100%;
    padding: 5px 12px 5px 28px;
    border-radius: 999px;
    background: var(--input-bg);
    border: 1px solid var(--glass-line-soft);
    font-size: 12.5px;
    outline: 0;
  }
  #filter:focus { border-color: var(--acc2); }

  /* Appearance Popover */
  #cfg {
    position: absolute;
    top: 136px;
    right: 24px;
    z-index: 25;
    width: 312px;
    padding: 16px;
    border-radius: 22px;
    background: var(--glass-pop);
    border: 1px solid var(--glass-line);
    -webkit-backdrop-filter: blur(42px) saturate(200%);
    backdrop-filter: blur(42px) saturate(200%);
    box-shadow: var(--glass-sh), 0 26px 70px rgba(0, 0, 0, 0.48);
    animation: popIn 0.2s var(--ease);
  }
  @keyframes popIn {
    from { opacity: 0; transform: translateY(-6px) scale(0.97); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }
  #cfg h4 {
    margin: 13px 0 7px;
    font-size: 10.5px;
    font-weight: 700;
    color: var(--mut);
    text-transform: uppercase;
    letter-spacing: 0.07em;
  }
  #cfg h4:first-child { margin-top: 0; }
  .seg {
    display: flex;
    padding: 3px;
    gap: 2px;
    border-radius: 999px;
    background: var(--input-bg);
  }
  .seg button {
    flex: 1;
    padding: 5px 0;
    border-radius: 999px;
    background: none;
    font-weight: 600;
    font-size: 12.5px;
    color: var(--mut);
    transition: background 0.15s, color 0.15s;
  }
  .seg button.on {
    background: var(--glass-hi);
    color: var(--fg);
    box-shadow: 0 1px 4px rgba(0,0,0,0.18);
  }
  .sl { display: flex; align-items: center; gap: 10px; font-size: 12.5px; }
  .sl input { flex: 1; }
  .sl-val { width: 38px; text-align: right; color: var(--mut); font-variant-numeric: tabular-nums; font-size: 12px; }
  .bgs { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; }
  .bgs button {
    height: 44px;
    border-radius: 12px;
    border: 2px solid transparent;
    background-size: cover;
    background-position: center;
    color: #fff;
    font-size: 11px;
    font-weight: 600;
    text-shadow: 0 1px 4px rgba(0,0,0,0.85);
    box-shadow: 0 2px 8px rgba(0,0,0,0.28);
    transition: transform 0.12s, border-color 0.15s;
  }
  .bgs button:hover { transform: scale(1.03); }
  .bgs button.on { border-color: var(--acc2); }

  /* File list */
  #list {
    flex: 1 1 auto;
    min-height: 0;
    overflow: auto;
    padding: 8px;
    border-radius: 22px;
  }
  #list::-webkit-scrollbar { width: 6px; }
  #list::-webkit-scrollbar-thumb { background: var(--glass-line-soft); border-radius: 99px; }

  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 9px 12px;
    border-radius: 14px;
    transition: background 0.12s, border-color 0.12s;
    cursor: pointer;
    border: 1px solid transparent;
  }
  .row:hover { background: var(--row-hover); }
  .row.sel {
    background: linear-gradient(90deg, rgba(255, 90, 54, 0.16), rgba(255, 138, 61, 0.06));
    border-color: rgba(255, 90, 54, 0.45);
  }
  .row .ic {
    width: 34px;
    height: 34px;
    border-radius: 10px;
    display: grid;
    place-items: center;
    flex: none;
  }
  .row.video .ic {
    color: #fff;
    background: linear-gradient(135deg, var(--acc), var(--acc2));
    box-shadow: 0 3px 10px var(--acc-glow);
  }
  .row.dir .ic {
    color: var(--blue);
    background: rgba(10, 132, 255, 0.14);
  }
  .thumb { position: relative; overflow: hidden; }
  .thumb img {
    position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
    opacity: 0; transition: opacity 0.25s;
  }
  .thumb img.ok { opacity: 1; }
  .thumb svg { position: relative; }
  .thumb.loaded svg { display: none; }
  .row.video .ic.thumb { width: 60px; height: 34px; border-radius: 8px; }
  .rcard-ic.thumb { width: 100%; }
  .row-body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .row .nm {
    font-weight: 500;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .row-prog { width: 120px; height: 3px; border-radius: 99px; background: var(--glass-line-soft); overflow: hidden; }
  .row-prog > i { display: block; height: 100%; background: var(--acc2); border-radius: 99px; }
  .row-meta { display: flex; align-items: center; gap: 8px; flex: none; }
  .ext-tag {
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: 0.04em;
    padding: 2px 7px;
    border-radius: 6px;
    background: var(--glass-line-soft);
    color: var(--mut);
  }
  .row .sz {
    color: var(--mut);
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    min-width: 60px;
    text-align: right;
  }
  /* List view (default) + poster grid view */
  #list {
    display: flex; flex-direction: column; gap: 4px; padding: 10px;
  }
  #list.grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 16px;
    align-content: start;
    padding: 14px;
  }
  #list .empty { grid-column: 1 / -1; }
  .row { transition: transform 0.2s var(--ease), background 0.15s, border-color 0.15s, box-shadow 0.2s; }
  #list.grid .row.video {
    flex-direction: column; align-items: stretch; gap: 9px;
    padding: 7px 7px 12px; border-radius: 18px; background: var(--glass-line-soft); align-self: start;
  }
  #list.grid .row.video:hover { transform: translateY(-3px); box-shadow: 0 14px 30px rgba(0,0,0,0.38); }
  #list.grid .row.video:active { transform: scale(0.985); }
  #list.grid .row.video .ic.thumb {
    width: 100%; height: auto; aspect-ratio: 16 / 9; border-radius: 12px;
    background: linear-gradient(135deg, rgba(255,90,54,0.55), rgba(255,138,61,0.35));
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08), 0 6px 16px rgba(0,0,0,0.3);
  }
  #list.grid .row.video .ic.thumb svg { width: 26px; height: 26px; }
  #list.grid .row.video .ic.thumb::after {
    content: ""; position: absolute; inset: 0; opacity: 0; transition: opacity 0.2s;
    background: radial-gradient(circle at center, rgba(0,0,0,0.05), rgba(0,0,0,0.45));
  }
  #list.grid .row.video:hover .ic.thumb::after { opacity: 1; }
  #list.grid .row.video .row-body { padding: 0 4px; gap: 6px; }
  #list.grid .row.video .nm { font-size: 13.5px; font-weight: 600; letter-spacing: -0.005em; }
  #list.grid .row.video .row-prog { width: 100%; height: 4px; }
  #list.grid .row.video .row-meta { padding: 0 4px; justify-content: space-between; }
  #list.grid .row.video .sz { min-width: 0; text-align: left; }
  .folders { grid-column: 1 / -1; width: 100%; display: flex; flex-wrap: wrap; gap: 8px; }
  .row.dir {
    padding: 7px 14px 7px 8px; border-radius: 999px; gap: 9px;
    background: var(--glass-line-soft); border: 1px solid var(--glass-line-soft);
  }
  .row.dir:hover { transform: translateY(-1px); background: var(--row-hover); }
  .row.dir .ic { width: 28px; height: 28px; border-radius: 50%; }
  .row.dir .ic svg { width: 14px; height: 14px; }
  .row.dir .nm { font-weight: 600; font-size: 13px; }
  .row.dir .row-meta { display: none; }
  .row.sel { box-shadow: 0 0 0 2px rgba(255,90,54,0.6), 0 14px 30px rgba(255,90,54,0.18); }
  @media (max-width: 640px) { #list.grid { grid-template-columns: repeat(2, 1fr); gap: 10px; padding: 10px; } }
  .empty { color: var(--mut); padding: 48px 16px; text-align: center; font-size: 14px; }

  /* ==================== DETAIL INSPECTOR MODAL ==================== */
  #detail {
    position: fixed;
    inset: 0;
    z-index: 30;
    display: grid;
    place-items: center;
    padding: 20px;
    background: var(--modal-scrim);
    -webkit-backdrop-filter: blur(18px);
    backdrop-filter: blur(18px);
  }
  #detail .card {
    position: relative;
    width: min(460px, 100%);
    max-height: 92vh;
    overflow: auto;
    padding: 26px;
    border-radius: 26px;
    background: var(--glass-pop);
    border: 1px solid var(--glass-line);
    -webkit-backdrop-filter: blur(44px) saturate(200%);
    backdrop-filter: blur(44px) saturate(200%);
    box-shadow: var(--glass-sh), 0 32px 96px rgba(0, 0, 0, 0.55);
    animation: popIn 0.22s var(--ease);
  }
  #x {
    position: absolute;
    top: 14px;
    right: 14px;
    width: 30px;
    height: 30px;
    border-radius: 999px;
    background: var(--glass-line-soft);
    color: var(--mut);
    font-size: 15px;
    display: grid;
    place-items: center;
  }
  #x:hover { background: var(--row-hover); color: var(--fg); }
  #detail h2 {
    margin: 0 0 8px;
    padding-right: 34px;
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.02em;
    line-height: 1.28;
    word-break: break-word;
  }
  .meta-pills {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 8px;
  }
  .meta-pill {
    font-size: 11.5px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    padding: 3px 9px;
    border-radius: 999px;
    background: var(--glass-line-soft);
    color: var(--mut);
  }
  .mut { color: var(--mut); font-size: 12.5px; }
  label.l {
    display: block;
    font-size: 11px;
    font-weight: 700;
    color: var(--mut);
    margin: 16px 0 6px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  select {
    width: 100%;
    padding: 10px 34px 10px 13px;
    border-radius: 13px;
    background-color: var(--input-bg);
    border: 1px solid var(--glass-line-soft);
    outline: 0;
    appearance: none;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' fill='none' stroke='%23999' stroke-width='2' stroke-linecap='round'%3E%3Cpath d='M1 1.5l5 5 5-5'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 12px center;
    font-size: 13.5px;
    transition: border-color 0.15s;
  }
  select:focus { border-color: var(--acc2); }
  select option { background: var(--opt-bg); color: var(--fg); }
  .play-actions {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 22px;
  }
  #play, #resume { width: 100%; padding: 12px 16px; font-size: 15px; }
  .err { color: var(--danger); font-size: 13px; margin-top: 12px; }

  /* ==================== CINEMA PLAYER ==================== */
  #player {
    position: fixed;
    inset: 0;
    background: #000;
    z-index: 40;
    user-select: none;
    overflow: hidden;
    color: #fff;
  }
  #player.idle { cursor: none; }
  video {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    background: #000;
  }

  /* Subtitles */
  #cueWrap {
    position: absolute;
    left: 6%;
    right: 6%;
    bottom: 7%;
    display: flex;
    justify-content: center;
    pointer-events: none;
    transition: bottom 0.28s var(--ease);
  }
  #player:not(.idle) #cueWrap { bottom: 138px; }
  #cue {
    max-width: 900px;
    text-align: center;
    white-space: pre-line;
    line-height: 1.36;
    font-size: calc(clamp(18px, 2.5vw, 42px) * var(--sub-scale));
    font-weight: 600;
    color: #fff;
  }
  #cue:empty { display: none; }
  #player[data-substyle="pill"] #cue {
    padding: 0.24em 0.62em;
    border-radius: 0.38em;
    background: rgba(14, 14, 18, 0.72);
    -webkit-backdrop-filter: blur(16px);
    backdrop-filter: blur(16px);
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.6);
  }
  #player[data-substyle="classic"] #cue {
    text-shadow: 0 0 4px #000, 0 0 8px #000, 0 2px 12px rgba(0,0,0,0.95);
  }
  #player[data-substyle="contrast"] #cue {
    padding: 0.18em 0.52em;
    border-radius: 0.2em;
    background: rgba(0, 0, 0, 0.92);
    color: #fff799;
  }

  /* Spinner & Center HUD */
  #spin {
    position: absolute;
    top: 50%; left: 50%;
    width: 52px; height: 52px;
    margin: -26px;
    border-radius: 50%;
    border: 3.5px solid rgba(255, 255, 255, 0.16);
    border-top-color: var(--acc2);
    animation: sp 0.78s linear infinite;
    pointer-events: none;
  }
  @keyframes sp { to { transform: rotate(360deg); } }

  #hud {
    position: absolute;
    top: 50%; left: 50%;
    transform: translate(-50%, -50%) scale(0.92);
    padding: 14px 22px;
    border-radius: 999px;
    background: rgba(20, 20, 26, 0.72);
    border: 1px solid rgba(255, 255, 255, 0.18);
    -webkit-backdrop-filter: blur(26px) saturate(180%);
    backdrop-filter: blur(26px) saturate(180%);
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 16px;
    font-weight: 600;
    color: #fff;
    opacity: 0;
    pointer-events: none;
  }
  #hud svg { width: 24px; height: 24px; }
  #hud.go { animation: hudFlash 0.68s var(--ease); }
  @keyframes hudFlash {
    0% { opacity: 0; transform: translate(-50%, -50%) scale(0.84); }
    20% { opacity: 1; transform: translate(-50%, -50%) scale(1); }
    75% { opacity: 1; transform: translate(-50%, -50%) scale(1); }
    100% { opacity: 0; transform: translate(-50%, -50%) scale(1.06); }
  }

  #perr {
    position: absolute;
    top: 50%; left: 50%;
    transform: translate(-50%, -50%);
    background: rgba(24, 24, 28, 0.9);
    border: 1px solid rgba(255, 255, 255, 0.16);
    -webkit-backdrop-filter: blur(24px);
    backdrop-filter: blur(24px);
    padding: 16px 24px;
    border-radius: 18px;
    max-width: min(460px, 86%);
    text-align: center;
    color: #fff;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.6);
  }

  /* Top player bar */
  #top {
    position: absolute;
    top: 0; left: 0; right: 0;
    padding: 18px 24px 48px;
    display: flex;
    gap: 12px;
    align-items: center;
    background: linear-gradient(rgba(0,0,0,0.72), rgba(0,0,0,0));
    transition: opacity 0.25s var(--ease), transform 0.25s var(--ease);
  }
  #player.idle #top { opacity: 0; transform: translateY(-6px); pointer-events: none; }
  #ttl {
    font-weight: 600;
    font-size: 16px;
    letter-spacing: -0.015em;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .top-badge {
    font-size: 11px;
    font-weight: 700;
    padding: 3px 9px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.14);
    border: 1px solid rgba(255, 255, 255, 0.18);
    color: rgba(255, 255, 255, 0.9);
    flex: none;
  }

  /* Bottom floating Liquid Glass dock */
  #botWrap {
    position: absolute;
    left: 0; right: 0; bottom: 0;
    padding: 40px 22px 20px;
    background: linear-gradient(rgba(0,0,0,0), rgba(0,0,0,0.75));
    display: flex;
    justify-content: center;
    transition: opacity 0.25s var(--ease), transform 0.25s var(--ease);
  }
  #player.idle #botWrap { opacity: 0; transform: translateY(10px); pointer-events: none; }
  #bot {
    width: min(1120px, 100%);
    padding: 12px 16px 11px;
    border-radius: 22px;
    background: rgba(24, 24, 30, 0.62);
    border: 1px solid rgba(255, 255, 255, 0.18);
    -webkit-backdrop-filter: blur(32px) saturate(190%);
    backdrop-filter: blur(32px) saturate(190%);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.22), 0 18px 50px rgba(0, 0, 0, 0.52);
  }

  .seek-wrap { position: relative; padding: 2px 0 4px; }
  #seekTip {
    position: absolute;
    bottom: 24px;
    transform: translateX(-50%);
    padding: 3px 8px;
    border-radius: 7px;
    background: rgba(20, 20, 26, 0.88);
    border: 1px solid rgba(255, 255, 255, 0.18);
    font-size: 11.5px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    pointer-events: none;
    white-space: nowrap;
  }
  #seekTip.has-img { padding: 4px; border-radius: 10px; display: flex; flex-direction: column; align-items: center; gap: 4px; }
  #seekTip img { display: block; width: 200px; aspect-ratio: 16 / 9; object-fit: cover; border-radius: 7px; background: rgba(255,255,255,0.08); }
  #seekTip img[hidden] { display: none; }

  .bar {
    display: flex;
    align-items: center;
    gap: 5px;
    margin-top: 4px;
    flex-wrap: nowrap;
    min-width: 0;
  }
  .bar > * { flex-shrink: 0; }
  .bar > .pop { flex-shrink: 1; min-width: 0; }
  .pb {
    background: transparent;
    width: 34px;
    height: 34px;
    border-radius: 999px;
    display: grid;
    place-items: center;
    color: #fff;
    transition: background 0.14s, transform 0.1s;
  }
  .pb:hover { background: rgba(255, 255, 255, 0.16); }
  .pb:active { transform: scale(0.92); }
  .pb.txt {
    width: auto;
    padding: 0 13px 0 8px;
    display: inline-flex;
    align-items: center;
    gap: 3px;
    white-space: nowrap;
    flex: none;
    font-weight: 600;
    font-size: 13px;
    background: rgba(255, 255, 255, 0.13);
    border: 1px solid rgba(255, 255, 255, 0.22);
    -webkit-backdrop-filter: blur(20px);
    backdrop-filter: blur(20px);
  }
  .pb.txt:hover { background: rgba(255, 255, 255, 0.22); }
  .pb.skip { width: auto; padding: 0 9px; font-size: 12px; font-weight: 700; gap: 3px; display: inline-flex; }
  .pb.skip svg { width: 15px; height: 15px; }
  .sp { flex: 1; min-width: 8px; }
  .tm {
    font-variant-numeric: tabular-nums;
    font-size: 12.5px;
    font-weight: 500;
    color: rgba(255, 255, 255, 0.9);
    padding: 4px 8px;
    border-radius: 8px;
    cursor: pointer;
    white-space: nowrap;
  }
  .tm:hover { background: rgba(255, 255, 255, 0.12); }

  .pop {
    background-color: rgba(255, 255, 255, 0.12);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 999px;
    padding: 6px 26px 6px 11px;
    font-size: 12.5px;
    font-weight: 500;
    color: #fff;
    width: auto;
    max-width: 150px;
    text-overflow: ellipsis;
    background-position: right 9px center;
  }
  .pop option { background: #1c1c20; color: #f5f5f7; }
  .sub-sync {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    padding: 2px 6px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.15);
    font-size: 11.5px;
    font-variant-numeric: tabular-nums;
  }
  .sub-sync button {
    background: none;
    color: #fff;
    width: 22px; height: 22px;
    border-radius: 999px;
    font-weight: 700;
  }
  .sub-sync button:hover { background: rgba(255, 255, 255, 0.18); }

  /* Range sliders */
  input[type=range] {
    -webkit-appearance: none;
    appearance: none;
    background: transparent;
    height: 18px;
    cursor: pointer;
    margin: 0;
    --p: 0%;
    --b: 0%;
  }
  input[type=range]::-webkit-slider-runnable-track {
    height: 5px;
    border-radius: 99px;
    background: linear-gradient(
      90deg,
      var(--acc) 0%,
      var(--acc2) var(--p),
      rgba(255, 255, 255, 0.36) var(--p),
      rgba(255, 255, 255, 0.36) var(--b),
      rgba(255, 255, 255, 0.18) var(--b)
    );
  }
  html[data-theme="light"] #cfg input[type=range]::-webkit-slider-runnable-track {
    background: linear-gradient(
      90deg,
      var(--acc) 0%,
      var(--acc2) var(--p),
      rgba(0, 0, 0, 0.14) var(--p),
      rgba(0, 0, 0, 0.14) 100%
    );
  }
  input[type=range]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #fff;
    margin-top: -4.5px;
    box-shadow: 0 1px 6px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(0, 0, 0, 0.1);
    transition: transform 0.12s;
  }
  input[type=range]:hover::-webkit-slider-thumb { transform: scale(1.16); }
  #seek { width: 100%; }
  #vol { width: 76px; flex: none; }
  @media (max-width: 900px) { .bar { flex-wrap: wrap; } .pop { max-width: 120px; } }

  /* Shortcuts overlay */
  #keysModal {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: grid;
    place-items: center;
    padding: 20px;
    background: rgba(0, 0, 0, 0.52);
    -webkit-backdrop-filter: blur(14px);
    backdrop-filter: blur(14px);
  }
  .keys-card {
    width: min(420px, 100%);
    padding: 22px 24px;
    border-radius: 24px;
    background: rgba(26, 26, 32, 0.86);
    border: 1px solid rgba(255, 255, 255, 0.18);
    box-shadow: 0 28px 80px rgba(0, 0, 0, 0.65);
    color: #fff;
  }
  .keys-card h3 { margin: 0 0 14px; font-size: 16px; font-weight: 700; display: flex; justify-content: space-between; align-items: center; }
  .keys-grid {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 9px 14px;
    font-size: 13px;
    align-items: center;
  }
  kbd {
    font: 600 11.5px var(--mono);
    padding: 3px 8px;
    border-radius: 7px;
    background: rgba(255, 255, 255, 0.12);
    border: 1px solid rgba(255, 255, 255, 0.18);
    justify-self: end;
    white-space: nowrap;
  }
</style>
</head>
<body>
<svg style="display:none">
  <symbol id="i-play" viewBox="0 0 24 24"><path d="M7 5.5c0-1.1 1.2-1.8 2.2-1.2l10.2 6.5c.9.6.9 1.9 0 2.4L9.2 19.7C8.2 20.3 7 19.6 7 18.5V5.5z"/></symbol>
  <symbol id="i-pause" viewBox="0 0 24 24"><rect x="6" y="4.5" width="4.2" height="15" rx="1.6"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.6"/></symbol>
  <symbol id="i-back" viewBox="0 0 24 24"><path d="M15.2 6.2a1 1 0 0 1 0 1.4L10.8 12l4.4 4.4a1 1 0 0 1-1.4 1.4l-5.1-5.1a1 1 0 0 1 0-1.4l5.1-5.1a1 1 0 0 1 1.4 0z"/></symbol>
  <symbol id="i-rew" viewBox="0 0 24 24"><path d="M12 5V2.2L7 6l5 3.8V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z"/></symbol>
  <symbol id="i-fwd" viewBox="0 0 24 24"><path d="M12 5V2.2L17 6l-5 3.8V7a5 5 0 1 0 5 5h2a7 7 0 1 1-7-7z"/></symbol>
  <symbol id="i-vol" viewBox="0 0 24 24"><path d="M3 9v6h4l5 4.5V4.5L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4zM14 3.4v2.1a7 7 0 0 1 0 13v2.1a9 9 0 0 0 0-17.2z"/></symbol>
  <symbol id="i-mute" viewBox="0 0 24 24"><path d="M16.5 12A4.5 4.5 0 0 0 14 8v2.2l2.4 2.4c.1-.2.1-.4.1-.6zM19 12a6.9 6.9 0 0 1-.9 3.3l1.5 1.5A9 9 0 0 0 21 12a9 9 0 0 0-7-8.8v2.1A7 7 0 0 1 19 12zM4.3 3 3 4.3 7.7 9H3v6h4l5 4.5v-6.2l4.2 4.2c-.7.5-1.4.9-2.2 1.1v2.1a9 9 0 0 0 3.7-1.8l2 2 1.3-1.3L12 8zM12 4.5 9.9 6.5 12 8.6z"/></symbol>
  <symbol id="i-fs" viewBox="0 0 24 24"><path d="M7 14H5v5h5v-2H7zm-2-4h2V7h3V5H5zm12 7h-3v2h5v-5h-2zM14 5v2h3v3h2V5z"/></symbol>
  <symbol id="i-pip" viewBox="0 0 24 24"><path d="M19 11h-8v6h8v-6zm4 8V5a2 2 0 0 0-2-2H3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2zm-2 0H3V5h18v14z"/></symbol>
  <symbol id="i-folder" viewBox="0 0 24 24"><path d="M10.2 5H4.5A2.5 2.5 0 0 0 2 7.5v9A2.5 2.5 0 0 0 4.5 19h15a2.5 2.5 0 0 0 2.5-2.5v-7A2.5 2.5 0 0 0 19.5 7H12l-1.8-2z"/></symbol>
  <symbol id="i-film" viewBox="0 0 24 24"><path d="M18 4v1.5h-2V4H8v1.5H6V4H4v16h2v-1.5h2V20h8v-1.5h2V20h2V4h-2zM8 17H6v-2h2v2zm0-4H6v-2h2v2zm0-4H6V7h2v2zm10 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V7h2v2z"/></symbol>
  <symbol id="i-search" viewBox="0 0 24 24"><path d="M10.5 3a7.5 7.5 0 1 0 4.7 13.3l4.2 4.2 1.4-1.4-4.2-4.2A7.5 7.5 0 0 0 10.5 3zm0 2a5.5 5.5 0 1 1 0 11 5.5 5.5 0 0 1 0-11z"/></symbol>
  <symbol id="i-sliders" viewBox="0 0 24 24"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></symbol>
  <symbol id="i-help" viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 15.2a1.2 1.2 0 1 1 0-2.4 1.2 1.2 0 0 1 0 2.4zm1.5-4.7c-.7.5-.8.8-.8 1.5h-1.8c0-1.3.4-2 1.3-2.6.8-.5 1.2-.9 1.2-1.6 0-.9-.7-1.5-1.7-1.5-1 0-1.7.6-1.8 1.6H8.1C8.2 7.8 9.8 6.5 12 6.5c2 0 3.5 1.2 3.5 3.1 0 1.3-.7 2.1-2 2.9z"/></symbol>
</svg>

<div id="lib">
  <div class="main">
    <header class="hero">
      <div class="app-badge"><img src="/assets/favicon.svg" alt=""></div>
      <div class="hero-title">
        <h1>Video Player</h1>
        <span>Kitbag Local Cinema</span>
      </div>
      <div class="hero-sp"></div>
      <div class="quick-pills" id="quickPills">
        <button class="pill-btn" data-dir="~/Movies">Movies</button>
        <button class="pill-btn" data-dir="~/Downloads">Downloads</button>
        <button class="pill-btn" data-dir="~/Desktop">Desktop</button>
        <button class="pill-btn" data-dir="~">Home</button>
      </div>
    </header>

    <div class="tools glass">
      <div class="toolbar">
        <button class="btn nav" id="navBack" title="Parent folder (⌘↑ or ⌘[)" disabled><svg><use href="#i-back"/></svg></button>
        <button class="btn nav" id="navFwd" title="Open folder (⌘↓ or ⌘])" disabled><svg style="transform:rotate(180deg)"><use href="#i-back"/></svg></button>
        <input class="field" id="dir" placeholder="Type a path and press Enter, e.g. ~/Movies" spellcheck="false" autocomplete="off" autocapitalize="off">
        <button class="btn primary" id="pick">Choose File…</button>
        <button class="btn nav" id="cfgBtn" title="Appearance"><svg><use href="#i-sliders"/></svg></button>
      </div>
      <div class="subbar">
        <div class="crumbs" id="crumbs"></div>
        <div class="view-toggle" id="viewToggle">
          <button data-v="list" title="List view"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg></button>
          <button data-v="grid" title="Grid view"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="4" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5"/></svg></button>
        </div>
        <div class="filter-wrap">
          <svg><use href="#i-search"/></svg>
          <input id="filter" placeholder="Filter folder (/)" spellcheck="false" autocomplete="off">
        </div>
      </div>
    </div>

    <div id="cfg" hidden>
      <h4>Theme</h4>
      <div class="seg" id="cTheme">
        <button data-v="system">System</button>
        <button data-v="dark">Dark</button>
        <button data-v="light">Light</button>
      </div>
      <h4>Glass Material</h4>
      <div class="seg" id="cStyle">
        <button data-v="clear">Clear</button>
        <button data-v="tinted">Tinted</button>
      </div>
      <h4>Translucency</h4>
      <div class="sl"><input type="range" id="cA" min="0" max="100"><span class="sl-val" id="vA">42%</span></div>
      <h4>Backdrop Blur</h4>
      <div class="sl"><input type="range" id="cB" min="0" max="60"><span class="sl-val" id="vB">28px</span></div>
      <h4>Background Dimming</h4>
      <div class="sl"><input type="range" id="cD" min="0" max="85"><span class="sl-val" id="vD">42%</span></div>
      <h4>Background</h4>
      <div class="bgs" id="cBg"></div>
    </div>

    <div id="list" class="glass"></div>
  </div>

  <aside id="detail" hidden>
    <div class="card">
      <button id="x" title="Close (Esc)">✕</button>
      <div id="panel" hidden>
        <h2 id="name"></h2>
        <div class="meta-pills" id="metaPills"></div>
        <div class="mut" id="meta"></div>
        <label class="l">Audio Track</label>
        <select id="audio"></select>
        <label class="l">Subtitles</label>
        <select id="sub"></select>
        <label class="l">Video Quality</label>
        <select id="qual">
          <option value="orig">Original</option>
          <option value="enhance">Enhanced (Denoise + Sharpen)</option>
          <option value="1080">Upscale to 1080p</option>
          <option value="1440">Upscale to 1440p</option>
          <option value="2160">Upscale to 4K</option>
        </select>
        <div class="mut" id="qhint" style="margin-top:6px"></div>
        <div class="play-actions">
          <button class="btn primary" id="resume" hidden></button>
          <button class="btn primary" id="play"><svg><use href="#i-play"/></svg><span id="playLbl">Play</span></button>
        </div>
        <div class="err" id="status"></div>
      </div>
    </div>
  </aside>
</div>

<div id="player" data-substyle="pill" hidden>
  <video id="v" playsinline></video>
  <div id="cueWrap"><div id="cue"></div></div>
  <div id="spin" hidden></div>
  <div id="hud"><svg><use id="hudIc" href="#i-play"/></svg><span id="hudTxt"></span></div>
  <div id="perr" hidden></div>

  <div id="top">
    <button class="pb txt" id="back"><svg><use href="#i-back"/></svg>Library</button>
    <div id="ttl"></div>
    <span class="top-badge" id="qualBadge" hidden></span>
    <span class="sp"></span>
    <button class="pb" id="pip" title="Picture in Picture (P)" hidden><svg><use href="#i-pip"/></svg></button>
    <button class="pb" id="keysBtn" title="Keyboard shortcuts (?)"><svg><use href="#i-help"/></svg></button>
  </div>

  <div id="botWrap">
    <div id="bot">
      <div class="seek-wrap">
        <div id="seekTip" hidden><img id="seekImg" alt="" hidden><span id="seekTime">0:00</span></div>
        <input type="range" id="seek" min="0" max="1" step="0.1" value="0">
      </div>
      <div class="bar">
        <button class="pb" id="pp" title="Play/Pause (Space)"><svg><use id="ppIc" href="#i-play"/></svg></button>
        <button class="pb skip" id="mSkip" title="Skip back (←)"><svg><use href="#i-rew"/></svg><span id="mSkipLbl">10</span></button>
        <button class="pb skip" id="pSkip" title="Skip forward (→)"><svg><use href="#i-fwd"/></svg><span id="pSkipLbl">10</span></button>
        <button class="pb" id="mute" title="Mute (M)"><svg><use id="muteIc" href="#i-vol"/></svg></button>
        <input type="range" id="vol" min="0" max="1" step="0.01" value="1">
        <span class="tm" id="time" title="Click to toggle remaining time">0:00 / 0:00</span>
        <span class="sp"></span>
        <div class="sub-sync" id="subSync" hidden title="Subtitle timing offset (G / H)">
          <button id="subMinus" title="Earlier 0.5s (G)">−</button>
          <span id="subOffTxt">0.0s</span>
          <button id="subPlus" title="Later 0.5s (H)">+</button>
        </div>
        <select class="pop" id="speed" title="Playback speed">
          <option value="0.5">0.5×</option>
          <option value="0.75">0.75×</option>
          <option value="1" selected>1×</option>
          <option value="1.25">1.25×</option>
          <option value="1.5">1.5×</option>
          <option value="1.75">1.75×</option>
          <option value="2">2×</option>
        </select>
        <select class="pop" id="pq" title="Video quality">
          <option value="orig">Original</option>
          <option value="enhance">Enhanced</option>
          <option value="1080">1080p</option>
          <option value="1440">1440p</option>
          <option value="2160">4K</option>
        </select>
        <select class="pop" id="paud" title="Audio track"></select>
        <select class="pop" id="psub" title="Subtitles"></select>
        <button class="pb" id="fs" title="Fullscreen (F)"><svg><use href="#i-fs"/></svg></button>
      </div>
    </div>
  </div>
</div>

<div id="keysModal" hidden>
  <div class="keys-card">
    <h3>Keyboard Shortcuts <button class="pb" id="keysClose" style="width:28px;height:28px">✕</button></h3>
    <div class="keys-grid">
      <kbd>Space / K</kbd><span>Play or pause</span>
      <kbd>← / →</kbd><span id="kSkipDesc">Seek back / forward 10s</span>
      <kbd>Shift + ← / →</kbd><span>Seek back / forward 30s</span>
      <kbd>↑ / ↓</kbd><span>Volume up / down</span>
      <kbd>M</kbd><span>Mute or unmute</span>
      <kbd>C</kbd><span>Toggle subtitles</span>
      <kbd>G / H</kbd><span>Nudge subtitles ±0.5s</span>
      <kbd>F</kbd><span>Fullscreen</span>
      <kbd>P</kbd><span>Picture in Picture</span>
      <kbd>0 – 9</kbd><span>Jump to 0% – 90%</span>
      <kbd>Esc</kbd><span>Exit fullscreen or return to Library</span>
    </div>
  </div>
</div>

<script>
const $ = (id) => document.getElementById(id);
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, String(v)); } catch {} }
};
const api = async (u, opts) => {
  const r = await fetch(u, opts);
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
};
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmtSize = (b) => b > 1e9 ? (b / 1e9).toFixed(2) + ' GB' : b > 1e6 ? Math.round(b / 1e6) + ' MB' : Math.max(1, Math.round(b / 1e3)) + ' KB';
const fmt = (x) => {
  x = Math.max(0, Math.floor(x || 0));
  const h = Math.floor(x / 3600), m = Math.floor((x % 3600) / 60), s = x % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s).padStart(2, '0');
};
const icon = (id) => `<svg><use href="#${id}"/></svg>`;
const opt = (v, t) => Object.assign(document.createElement('option'), { value: String(v), textContent: t });
const trackLabel = (t) => `${(t.lang || 'und').toUpperCase()}${t.title ? ' – ' + t.title : ''} (${t.codec}${t.channels ? ', ' + t.channels + 'ch' : ''})${t.default ? ' ★' : ''}`;

/* ---------------- App Config (Live-Synced with Kitbag Settings) ---------------- */
const BGS = [
  ['desktop', 'Desktop', 'url(/api/wallpaper)'],
  ['aurora', 'Aurora', 'linear-gradient(135deg,#0f2027,#203a43 48%,#2c5364 76%,#1fa2a6)'],
  ['sunset', 'Sunset', 'linear-gradient(135deg,#2b1055,#9d2a49 55%,#f2994a)'],
  ['midnight', 'Midnight', 'linear-gradient(160deg,#050614,#161b40 58%,#3b2d70)'],
  ['ember', 'Ember', 'linear-gradient(135deg,#170a06,#7a2b0d 58%,#f37335)'],
  ['graphite', 'Graphite', 'linear-gradient(160deg,#18191e,#2c2e38 60%,#444857)'],
];
const SUB_SCALES = { small: 0.82, medium: 1.0, large: 1.24, extraLarge: 1.5 };

let cfg = {
  configVersion: 0,
  defaultFolder: '~/Movies',
  defaultQuality: 'orig',
  defaultSpeed: 1,
  skipSeconds: 10,
  preferredAudioLanguage: 'default',
  subtitleBehavior: 'auto',
  rememberPosition: true,
  hardwareAcceleration: true,
  theme: 'system',
  glassStyle: 'clear',
  glassTransparency: 42,
  glassBlur: 28,
  backgroundDimming: 42,
  backgroundPreset: 'desktop',
  customBackgroundPath: '',
  subtitleSize: 'medium',
  subtitleStyle: 'pill',
};
let recentsMap = new Map();
let patchTimer = null;

const darkMedia = window.matchMedia('(prefers-color-scheme: dark)');
function resolveTheme(mode) {
  if (mode === 'light' || mode === 'dark') return mode;
  return darkMedia.matches ? 'dark' : 'light';
}
darkMedia.addEventListener('change', () => { if (cfg.theme === 'system') applyConfig(cfg); });

const mix = (t, a, b) => a + (b - a) * (t / 100);
function paint(el, pct, buf) {
  el.style.setProperty('--p', Math.max(0, Math.min(100, pct)) + '%');
  el.style.setProperty('--b', Math.max(0, Math.min(100, Math.max(pct, buf ?? pct))) + '%');
}

function applyConfig(c) {
  cfg = Object.assign({}, cfg, c);
  const resolvedTheme = resolveTheme(cfg.theme);
  document.documentElement.setAttribute('data-theme', resolvedTheme);
  const metaTheme = document.querySelector('meta[name="theme-color"]');
  if (metaTheme) metaTheme.content = resolvedTheme === 'dark' ? '#0b0b0e' : '#eef0f4';

  const r = document.documentElement.style;
  const tinted = cfg.glassStyle === 'tinted';
  r.setProperty('--ga', mix(cfg.glassTransparency, 0.02, tinted ? 0.34 : 0.25).toFixed(3));
  r.setProperty('--gt', tinted ? '0.32' : '0');
  r.setProperty('--gb', Math.round(cfg.glassBlur) + 'px');
  r.setProperty('--dim', (cfg.backgroundDimming / 100).toFixed(2));
  r.setProperty('--sub-scale', String(SUB_SCALES[cfg.subtitleSize] || 1));
  $('player').setAttribute('data-substyle', cfg.subtitleStyle || 'pill');

  const cust = cfg.backgroundPreset === 'custom' && cfg.customBackgroundPath;
  const preset = BGS.find((x) => x[0] === cfg.backgroundPreset) || BGS[0];
  r.setProperty('--bgi', cust ? `url(/api/bgimg?path=${encodeURIComponent(cfg.customBackgroundPath)})` : preset[2]);

  // Update appearance popover controls
  $('cTheme').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.v === cfg.theme));
  $('cStyle').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.v === cfg.glassStyle));
  $('cA').value = cfg.glassTransparency; $('vA').textContent = Math.round(cfg.glassTransparency) + '%';
  $('cB').value = cfg.glassBlur; $('vB').textContent = Math.round(cfg.glassBlur) + 'px';
  $('cD').value = cfg.backgroundDimming; $('vD').textContent = Math.round(cfg.backgroundDimming) + '%';
  [['cA', 0, 100], ['cB', 0, 60], ['cD', 0, 85]].forEach(([id, lo, hi]) => paint($(id), (($(id).value - lo) / (hi - lo)) * 100));
  $('cBg').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.v === cfg.backgroundPreset));

  // Skip interval labels
  const sk = cfg.skipSeconds || 10;
  $('mSkipLbl').textContent = String(sk);
  $('pSkipLbl').textContent = String(sk);
  $('mSkip').title = `Skip back ${sk}s (←)`;
  $('pSkip').title = `Skip forward ${sk}s (→)`;
  $('kSkipDesc').textContent = `Seek back / forward ${sk}s`;
}

function pushPatch(patch) {
  Object.assign(cfg, patch);
  applyConfig(cfg);
  clearTimeout(patchTimer);
  patchTimer = setTimeout(() => {
    fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(patch),
    }).then((r) => r.json()).then((updated) => {
      if (updated && updated.configVersion) cfg.configVersion = updated.configVersion;
    }).catch(() => {});
  }, 140);
}

// Build background swatches
$('cBg').replaceChildren(
  ...BGS.map(([k, n, css]) => {
    const b = document.createElement('button');
    b.textContent = n;
    b.dataset.v = k;
    b.style.backgroundImage = css;
    b.onclick = () => pushPatch({ backgroundPreset: k });
    return b;
  }),
  (() => {
    const b = document.createElement('button');
    b.textContent = 'Image…';
    b.dataset.v = 'custom';
    b.style.background = 'rgba(128,128,140,0.38)';
    b.onclick = async () => {
      try {
        const { path } = await api('/api/pick?kind=image');
        if (path) pushPatch({ customBackgroundPath: path, backgroundPreset: 'custom' });
      } catch {}
    };
    return b;
  })()
);
$('cTheme').onclick = (e) => { if (e.target.dataset.v) pushPatch({ theme: e.target.dataset.v }); };
$('cStyle').onclick = (e) => { if (e.target.dataset.v) pushPatch({ glassStyle: e.target.dataset.v }); };
$('cA').oninput = () => pushPatch({ glassTransparency: +$('cA').value });
$('cB').oninput = () => pushPatch({ glassBlur: +$('cB').value });
$('cD').oninput = () => pushPatch({ backgroundDimming: +$('cD').value });
$('cfgBtn').onclick = (e) => { e.stopPropagation(); $('cfg').hidden = !$('cfg').hidden; };
document.addEventListener('click', (e) => {
  if (!$('cfg').hidden && !$('cfg').contains(e.target) && e.target !== $('cfgBtn')) $('cfg').hidden = true;
});

/* Thumbnails: lazy-loaded video frames; the icon stays as the fallback. */
const thumbObs = new IntersectionObserver((entries) => {
  for (const en of entries) {
    if (!en.isIntersecting) continue;
    const img = en.target;
    thumbObs.unobserve(img);
    img.src = img.dataset.src;
  }
}, { rootMargin: '200px' });
function thumbImg(p) {
  return `<img alt="" data-src="/api/thumb?file=${encodeURIComponent(p)}" onload="this.classList.add('ok');this.parentNode.classList.add('loaded')" onerror="this.remove()">`;
}
new MutationObserver(() => {
  document.querySelectorAll('img[data-src]:not([src])').forEach((i) => thumbObs.observe(i));
}).observe(document.body, { childList: true, subtree: true });

/* ---------------- Continue Watching ---------------- */
async function loadRecents() {
  try {
    const items = await api('/api/recents');
    recentsMap = new Map(items.map((x) => [x.path, x]));
  } catch {}
}

function savedPosition(filePath, duration) {
  if (!cfg.rememberPosition) return 0;
  const serverItem = recentsMap.get(filePath);
  const localPos = Number(store.get('pos:' + filePath)) || 0;
  const pos = (serverItem && serverItem.position > 0) ? serverItem.position : localPos;
  return (pos > 15 && (!duration || pos < duration - 30)) ? pos : 0;
}

/* ---------------- Library ---------------- */
let parent = '', cwd = '', current = null, probed = null, selToken = 0, lsToken = 0;
let lastChild = null, subDirs = [], currentEntries = [];

const downTarget = () => (lastChild && subDirs.includes(lastChild) ? lastChild : subDirs[0]);
function navState() {
  $('navBack').disabled = !cwd || cwd === '/';
  $('navFwd').disabled = !subDirs.length;
}
const goUp = () => parent && parent !== cwd && ls(parent);
const goDown = () => { const t = downTarget(); if (t) ls(t); };

function crumbs(dir) {
  const parts = dir.split('/').filter(Boolean);
  let acc = '';
  $('crumbs').replaceChildren();
  const add = (name, p) => {
    const b = document.createElement('button');
    b.textContent = name;
    b.onclick = () => ls(p);
    $('crumbs').append(b);
  };
  add('/', '/');
  parts.forEach((n) => {
    acc += '/' + n;
    $('crumbs').append(Object.assign(document.createElement('span'), { textContent: '›' }));
    add(n, acc);
  });
}

let viewMode = store.get('view') === 'grid' ? 'grid' : 'list';
function applyView() {
  $('list').classList.toggle('grid', viewMode === 'grid');
  document.querySelectorAll('#viewToggle button').forEach((b) => b.classList.toggle('active', b.dataset.v === viewMode));
}
document.querySelectorAll('#viewToggle button').forEach((b) => {
  b.onclick = () => { viewMode = b.dataset.v; store.set('view', viewMode); applyView(); };
});
applyView();

function renderList() {
  const q = ($('filter').value || '').trim().toLowerCase();
  const items = q ? currentEntries.filter((e) => e.name.toLowerCase().includes(q)) : currentEntries;
  $('list').replaceChildren();
  if (!items.length) {
    $('list').innerHTML = `<div class="empty">${q ? 'No matches in this folder.' : 'No folders or videos here.'}</div>`;
    return;
  }
  const strip = document.createElement('div');
  strip.className = 'folders';
  for (const e of items) {
    const el = document.createElement('div');
    el.className = 'row ' + e.type;
    el.dataset.path = e.path;
    const rec = e.type === 'video' ? recentsMap.get(e.path) : null;
    const pct = rec && rec.duration > 0 && rec.position > 15 ? Math.min(100, (rec.position / rec.duration) * 100) : 0;
    el.innerHTML = `
      <div class="ic${e.type === 'video' ? ' thumb' : ''}">${icon(e.type === 'dir' ? 'i-folder' : 'i-film')}${e.type === 'video' ? thumbImg(e.path) : ''}</div>
      <div class="row-body">
        <div class="nm">${esc(e.name)}</div>
        ${pct > 0 ? `<div class="row-prog"><i style="width:${pct}%"></i></div>` : ''}
      </div>
      <div class="row-meta">
        ${e.ext ? `<span class="ext-tag">${esc(e.ext)}</span>` : ''}
        ${e.size ? `<div class="sz">${fmtSize(e.size)}</div>` : ''}
      </div>
    `;
    el.onclick = () => e.type === 'dir' ? ls(e.path) : select(e, el);
    if (current && current.path === e.path) el.classList.add('sel');
    if (e.type === 'dir') strip.append(el); else $('list').append(el);
  }
  if (strip.childElementCount) $('list').prepend(strip);
}

async function ls(dir) {
  const tok = ++lsToken;
  try {
    const targetDir = dir || store.get('dir') || cfg.defaultFolder || '~/Movies';
    const d = await api('/api/ls?dir=' + encodeURIComponent(targetDir));
    if (tok !== lsToken) return;
    const prev = cwd, base = d.dir === '/' ? '/' : d.dir + '/';
    lastChild = prev && prev.startsWith(base) ? base + prev.slice(base.length).split('/')[0] : (lastChild && lastChild.startsWith(base) ? lastChild : null);
    subDirs = d.entries.filter((e) => e.type === 'dir').map((e) => e.path);
    currentEntries = d.entries;
    parent = d.parent;
    cwd = d.dir;
    $('dir').value = d.dir;
    $('filter').value = '';
    store.set('dir', d.dir);
    crumbs(d.dir);
    navState();
    $('quickPills').querySelectorAll('button').forEach((b) => {
      const suffix = b.dataset.dir.replace(/^~/, '');
      b.classList.toggle('active', suffix ? d.dir.endsWith(suffix) : d.dir.split('/').length === 3);
    });
    renderList();
    if (d.file) {
      const row = [...document.querySelectorAll('.row')].find((r) => r.dataset.path === d.file);
      await select({ name: d.file.split('/').pop(), path: d.file }, row);
      if (row) row.scrollIntoView({ block: 'center' });
    }
    return d;
  } catch (err) {
    currentEntries = [];
    $('list').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
    return null;
  }
}

$('quickPills').onclick = (e) => {
  const b = e.target.closest('button[data-dir]');
  if (b) ls(b.dataset.dir);
};
$('filter').oninput = renderList;

function pickPreferredAudio(audioTracks) {
  if (!audioTracks.length) return '1';
  const pref = cfg.preferredAudioLanguage;
  if (pref && pref !== 'default') {
    const match = audioTracks.find((t) => (t.lang || '').toLowerCase().startsWith(pref));
    if (match) return String(match.id);
  }
  const def = audioTracks.find((t) => t.default);
  return String(def ? def.id : audioTracks[0].id);
}

function pickPreferredSub(p) {
  const mode = cfg.subtitleBehavior || 'auto';
  if (mode === 'off') return 'no';
  if (mode === 'externalOnly') return p.external.length ? 'file:' + p.external[0].path : 'no';
  if (mode === 'defaultTrack') {
    const def = p.subs.find((t) => t.default);
    return def ? String(def.id) : 'no';
  }
  // auto: external first, else default eng/und, else first eng
  if (p.external.length) return 'file:' + p.external[0].path;
  const ds = p.subs.find((t) => t.default && /^(eng|und)$/i.test(t.lang)) || p.subs.find((t) => /^eng/i.test(t.lang));
  return ds ? String(ds.id) : 'no';
}

const QH = {
  orig: 'Direct stream copy for H.264 from 0:00, otherwise hardware-accelerated H.264.',
  enhance: 'Hardware re-encode with light denoise + crisp sharpening.',
  1080: 'Upscales smaller videos to 1080p with Lanczos + sharpening.',
  1440: 'Upscales smaller videos to 1440p with Lanczos + sharpening.',
  2160: 'Upscales smaller videos to 4K with Lanczos + sharpening.',
};

function updateQualityHint() {
  const q = $('qual').value;
  if (q === 'orig' && probed && probed.video) {
    const direct = probed.video.codec === 'h264' && probed.video.pix_fmt === 'yuv420p';
    $('qhint').textContent = direct
      ? 'Zero-loss H.264 stream copy from start (transcodes on seek).'
      : `Transcodes ${probed.video.codec.toUpperCase()} on the fly via ${cfg.hardwareAcceleration ? 'Apple VideoToolbox' : 'x264'}.`;
  } else {
    $('qhint').textContent = QH[q] || '';
  }
}

async function select(e, el) {
  const tok = ++selToken;
  document.querySelectorAll('.row.sel').forEach((x) => x.classList.remove('sel'));
  if (el) el.classList.add('sel');
  current = e;
  probed = null;
  $('qual').value = cfg.defaultQuality || 'orig';
  $('qhint').textContent = QH[$('qual').value] || '';
  $('detail').hidden = false;
  $('panel').hidden = false;
  $('name').textContent = e.name;
  $('status').textContent = '';
  $('metaPills').replaceChildren();
  $('meta').textContent = 'Reading media streams…';
  $('play').disabled = true;
  $('resume').hidden = true;
  $('play').className = 'btn primary';
  $('playLbl').textContent = 'Play';
  $('audio').replaceChildren();
  $('sub').replaceChildren();

  try {
    const p = await api('/api/probe?file=' + encodeURIComponent(e.path));
    if (tok !== selToken) return;
    probed = p;
    const pills = [fmt(p.duration)];
    if (p.video && p.video.width && p.video.height) pills.push(`${p.video.width}×${p.video.height}`);
    if (p.video && p.video.codec) pills.push(p.video.codec.toUpperCase());
    pills.push(`${p.audio.length} Audio`);
    const subTotal = p.subs.length + p.external.length;
    if (subTotal) pills.push(`${subTotal} Sub${subTotal === 1 ? '' : 's'}`);
    $('metaPills').replaceChildren(...pills.map((t) => Object.assign(document.createElement('span'), { className: 'meta-pill', textContent: t })));
    $('meta').textContent = '';

    $('audio').replaceChildren(...(p.audio.length ? p.audio.map((t) => opt(t.id, trackLabel(t))) : [opt('1', 'No audio track')]));
    $('audio').value = pickPreferredAudio(p.audio);

    $('sub').replaceChildren(
      opt('no', 'Off'),
      ...p.subs.map((t) => opt(t.id, trackLabel(t))),
      ...p.external.map((x) => opt('file:' + x.path, '📄 ' + x.name)),
      opt('browse', 'Browse for subtitle file…')
    );
    $('sub').value = pickPreferredSub(p);
    updateQualityHint();
    $('play').disabled = false;

    const pos = savedPosition(e.path, p.duration);
    if (pos > 0) {
      $('resume').innerHTML = `${icon('i-play')}Resume from ${fmt(pos)}`;
      $('resume').hidden = false;
      $('resume').onclick = () => start(pos);
      $('play').className = 'btn';
      $('playLbl').textContent = 'Play from Beginning';
    }
  } catch (err) {
    if (tok === selToken) {
      $('meta').textContent = '';
      $('status').textContent = 'Could not read this file: ' + err.message;
    }
  }
}

$('qual').onchange = updateQualityHint;
$('sub').onchange = async () => {
  if ($('sub').value !== 'browse') return;
  try {
    const { path } = await api('/api/pick?kind=subtitle');
    if (!path) { $('sub').value = 'no'; return; }
    const o = opt('file:' + path, '📄 ' + path.split('/').pop());
    $('sub').insertBefore(o, $('sub').lastChild);
    $('sub').value = o.value;
  } catch { $('sub').value = 'no'; }
};

$('pick').onclick = async () => {
  $('pick').disabled = true;
  try {
    const { path } = await api('/api/pick?kind=video');
    if (path) await openPathDirectly(path, false);
  } catch (err) {
    $('status').textContent = err.message;
  } finally {
    $('pick').disabled = false;
  }
};

async function openPathDirectly(filePath, autoStart) {
  const dir = filePath.slice(0, filePath.lastIndexOf('/')) || '/';
  await ls(dir);
  const row = [...document.querySelectorAll('.row')].find((r) => r.dataset.path === filePath);
  await select({ name: filePath.split('/').pop(), path: filePath }, row);
  if (row) row.scrollIntoView({ block: 'center' });
  if (autoStart && probed) {
    const pos = savedPosition(filePath, probed.duration);
    start(pos);
  }
}

$('dir').onkeydown = (e) => {
  if (e.key === 'Enter') { ls($('dir').value); $('dir').blur(); }
  else if (e.key === 'Escape') { $('dir').value = cwd; $('dir').blur(); }
};
$('dir').onfocus = () => $('dir').select();
$('navBack').onclick = goUp;
$('navFwd').onclick = goDown;

document.addEventListener('keydown', (e) => {
  if (!$('player').hidden) return;
  if (e.key === '/' && document.activeElement !== $('dir') && document.activeElement !== $('filter') && $('detail').hidden) {
    e.preventDefault(); $('filter').focus(); return;
  }
  if (!e.metaKey) return;
  if (e.key === '[') { e.preventDefault(); goUp(); }
  else if (e.key === ']') { e.preventDefault(); goDown(); }
  else if (e.key === 'ArrowUp' && e.target !== $('dir')) { e.preventDefault(); goUp(); }
  else if (e.key === 'ArrowDown' && e.target !== $('dir')) { e.preventDefault(); goDown(); }
});
document.addEventListener('mouseup', (e) => {
  if ($('player').hidden && (e.button === 3 || e.button === 4)) {
    e.preventDefault();
    (e.button === 3 ? goUp : goDown)();
  }
});

/* ---------------- Player ---------------- */
const v = $('v');
let P = null, offset = 0, cues = [], subOffset = 0, lastSubChoice = 'no';
let dragging = false, showRemaining = false, idleT, lastSave = 0;

const cur = () => offset + (v.currentTime || 0);
const dur = () => (P ? P.dur : 0);

function parseVTT(txt) {
  const ts = (s) => {
    const p = s.replace(',', '.').split(':').map(Number);
    while (p.length < 3) p.unshift(0);
    return p[0] * 3600 + p[1] * 60 + p[2];
  };
  return txt.replace(/\r/g, '').split(/\n\n+/).map((b) => {
    const l = b.split('\n');
    const i = l.findIndex((x) => x.includes('-->'));
    if (i < 0) return null;
    const [a, z] = l[i].split('-->');
    return {
      s: ts(a.trim()),
      e: ts(z.trim().split(' ')[0]),
      t: l.slice(i + 1).join('\n').replace(/<[^>]+>/g, '').replace(/\{[^}]*\}/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').trim(),
    };
  }).filter((c) => c && c.t).sort((a, b) => a.s - b.s);
}

function showErr(msg) { $('perr').textContent = msg; $('perr').hidden = !msg; }
function hud(iconId, text = '') {
  $('hudIc').setAttribute('href', iconId);
  $('hudTxt').textContent = text;
  $('hudTxt').hidden = !text;
  const h = $('hud');
  h.classList.remove('go');
  void h.offsetWidth;
  h.classList.add('go');
}

function updateQualBadge() {
  const q = $('pq').value;
  const map = { orig: '', enhance: 'Enhanced', 1080: '1080p Upscale', 1440: '1440p Upscale', 2160: '4K Upscale' };
  const txt = map[q] || (probed && probed.video && probed.video.height ? probed.video.height + 'p' : '');
  $('qualBadge').textContent = txt;
  $('qualBadge').hidden = !txt;
}

// Browsers with a hardware HEVC decoder can play HEVC as-is; the server then remuxes instead of re-encoding.
const hevcDirect = (() => {
  try { return document.createElement('video').canPlayType('video/mp4; codecs="hvc1.2.4.L153.B0, mp4a.40.2"') === 'probably'; }
  catch { return false; }
})();
let loadTok = 0;
async function load(t, autoplay = true) {
  t = Math.min(Math.max(0, t), Math.max(0, dur() - 1));
  const tok = ++loadTok;
  showErr('');
  $('spin').hidden = false;
  const direct = hevcDirect && $('pq').value === 'orig' && probed && probed.video && probed.video.codec === 'hevc';
  if (direct && t > 0) {
    try { t = (await api(`/api/keyframe?file=${encodeURIComponent(P.path)}&t=${t}`)).t; } catch {}
    if (tok !== loadTok) return;
  }
  offset = t;
  v.src = `/stream?file=${encodeURIComponent(P.path)}&aid=${$('paud').value || 1}&q=${$('pq').value}&t=${t}${direct ? '&vc=1' : ''}`;
  v.playbackRate = Number($('speed').value) || 1;
  if (autoplay) v.play().catch(() => {});
  paintTime(t);
  updateQualBadge();
}

async function setSub() {
  const val = $('psub').value, mine = ++setSub.n;
  cues = [];
  $('cue').textContent = '';
  $('subSync').hidden = (val === 'no');
  if (val === 'no') return;
  try {
    if (val === 'browse') {
      const { path } = await api('/api/pick?kind=subtitle');
      if (!path) { $('psub').value = setSub.last || 'no'; $('subSync').hidden = ($('psub').value === 'no'); return; }
      const o = opt('file:' + path, '📄 ' + path.split('/').pop());
      $('psub').insertBefore(o, $('psub').lastChild);
      $('psub').value = o.value;
      return setSub();
    }
    const q = val.startsWith('file:') ? 'ext=' + encodeURIComponent(val.slice(5)) : `file=${encodeURIComponent(P.path)}&sid=${val}`;
    const r = await fetch('/subs?' + q);
    if (!r.ok) throw new Error((await r.json()).error);
    const parsed = parseVTT(await r.text());
    if (mine === setSub.n) {
      cues = parsed;
      setSub.last = val;
      lastSubChoice = val;
      $('subSync').hidden = false;
    }
  } catch (e) {
    showErr(e.message || 'Subtitle error');
    setTimeout(() => showErr(''), 4200);
    $('psub').value = 'no';
    $('subSync').hidden = true;
  }
}
setSub.n = 0;

function nudgeSub(delta) {
  subOffset = Math.round((subOffset + delta) * 10) / 10;
  $('subOffTxt').textContent = (subOffset > 0 ? '+' : '') + subOffset.toFixed(1) + 's';
  hud('#i-sliders', `Subtitles ${$('subOffTxt').textContent}`);
}
$('subMinus').onclick = () => nudgeSub(-0.5);
$('subPlus').onclick = () => nudgeSub(0.5);

let pushedPlay = false;
function playUrl() {
  const u = new URLSearchParams({
    play: P.path,
    a: $('paud').value || '1',
    s: $('psub').value === 'browse' ? 'no' : $('psub').value,
    q: $('pq').value,
  });
  return '/?' + u;
}
function syncUrl() { if (P) history.replaceState(history.state, '', playUrl()); }

function start(at = 0) {
  if (!probed || !current) return;
  $('pq').value = $('qual').value;
  $('speed').value = String(cfg.defaultSpeed || 1);
  subOffset = 0;
  $('subOffTxt').textContent = '0.0s';

  let sv = $('sub').value;
  if (sv === 'browse') sv = 'no';
  P = { path: current.path, dur: probed.duration };

  $('paud').replaceChildren(...(probed.audio.length ? probed.audio.map((t) => opt(t.id, trackLabel(t))) : [opt('1', 'Audio')]));
  $('paud').value = $('audio').value;

  $('psub').replaceChildren(
    opt('no', 'Subtitles off'),
    ...probed.subs.map((t) => opt(t.id, trackLabel(t))),
    ...probed.external.map((x) => opt('file:' + x.path, '📄 ' + x.name)),
    opt('browse', 'Browse for subtitle file…')
  );
  $('psub').value = sv;
  if ($('psub').value !== sv) $('psub').value = 'no';
  if ($('psub').value !== 'no') lastSubChoice = $('psub').value;

  $('seek').max = P.dur;
  $('ttl').textContent = current.name;
  $('pip').hidden = !document.pictureInPictureEnabled;
  $('player').hidden = false;
  $('player').classList.remove('idle');
  document.title = current.name;

  if (!new URLSearchParams(location.search).has('play')) {
    history.pushState({ play: 1 }, '', playUrl());
    pushedPlay = true;
  } else {
    syncUrl();
  }
  v.volume = Number(store.get('vol') ?? 1);
  $('vol').value = v.volume;
  paintVol();
  setSub();
  load(at);
  wake();
}
$('play').onclick = () => start(0);

function paintTime(c) {
  if (!dragging) $('seek').value = c;
  const d = dur();
  const shown = dragging ? Number($('seek').value) : c;
  const pct = d ? Math.min(100, (shown / d) * 100) : 0;
  let buf = pct;
  try {
    if (v.buffered.length) buf = Math.min(100, ((offset + v.buffered.end(v.buffered.length - 1)) / d) * 100);
  } catch {}
  paint($('seek'), pct, buf);
  $('time').textContent = showRemaining
    ? `${fmt(shown)} / −${fmt(Math.max(0, d - shown))}`
    : `${fmt(shown)} / ${fmt(d)}`;
}
$('time').onclick = () => { showRemaining = !showRemaining; paintTime(cur()); };

function paintVol() {
  paint($('vol'), v.muted ? 0 : v.volume * 100);
  $('muteIc').setAttribute('href', v.muted || v.volume === 0 ? '#i-mute' : '#i-vol');
}

function toggle() {
  if (v.paused) { v.play().catch(() => {}); hud('#i-play'); }
  else { v.pause(); hud('#i-pause'); }
}
function jump(d) {
  load(cur() + d, !v.paused || v.ended);
  hud(d < 0 ? '#i-rew' : '#i-fwd', (d > 0 ? '+' : '') + d + 's');
}

$('pp').onclick = toggle;
v.onclick = toggle;
v.ondblclick = () => $('fs').click();
$('mSkip').onclick = () => jump(-(cfg.skipSeconds || 10));
$('pSkip').onclick = () => jump(cfg.skipSeconds || 10);
$('paud').onchange = () => { syncUrl(); load(cur(), !v.paused); };
$('pq').onchange = () => { syncUrl(); load(cur(), !v.paused); };
$('psub').onchange = () => { setSub().then(syncUrl); };
$('speed').onchange = () => { v.playbackRate = Number($('speed').value) || 1; };
$('mute').onclick = () => { v.muted = !v.muted; paintVol(); hud(v.muted ? '#i-mute' : '#i-vol', v.muted ? 'Muted' : `${Math.round(v.volume * 100)}%`); };
$('vol').oninput = () => { v.muted = false; v.volume = Number($('vol').value); store.set('vol', v.volume); paintVol(); };
$('seek').oninput = () => { dragging = true; paintTime(Number($('seek').value)); };
$('seek').onchange = () => { dragging = false; load(Number($('seek').value), !v.paused || v.ended); };
$('fs').onclick = () => document.fullscreenElement ? document.exitFullscreen() : $('player').requestFullscreen();
$('pip').onclick = () => {
  if (document.pictureInPictureElement) document.exitPictureInPicture().catch(() => {});
  else v.requestPictureInPicture?.().catch(() => {});
};

// Hover time preview on scrub bar (time + scene thumbnail)
let tipTimer = 0, tipReq = 0;
$('seek').onmousemove = (e) => {
  const d = dur();
  if (!d) return;
  const rect = $('seek').getBoundingClientRect();
  const ratio = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
  const t = ratio * d;
  $('seekTime').textContent = fmt(t);
  // keep the thumbnail fully inside the bar
  const half = 108, px = ratio * rect.width;
  const clamped = Math.min(rect.width - half, Math.max(half, px));
  $('seekTip').style.left = clamped + 'px';
  $('seekTip').hidden = false;
  clearTimeout(tipTimer);
  const my = ++tipReq;
  tipTimer = setTimeout(() => {
    const img = new Image();
    img.onload = () => {
      if (my !== tipReq) return;
      $('seekImg').src = img.src;
      $('seekImg').hidden = false;
      $('seekTip').classList.add('has-img');
    };
    img.src = `/api/frame?file=${encodeURIComponent(P.path)}&t=${Math.round(t)}`;
  }, 120);
};
$('seek').onmouseleave = () => { clearTimeout(tipTimer); tipReq++; $('seekTip').hidden = true; $('seekImg').hidden = true; $('seekTip').classList.remove('has-img'); };

function closePlayer() {
  if (pushedPlay && history.state && history.state.play) { history.back(); return; }
  history.replaceState(null, '', '/');
  hidePlayer();
}
function hidePlayer() {
  if ($('player').hidden) return;
  pushedPlay = false;
  save(true);
  v.pause();
  v.removeAttribute('src');
  v.load();
  $('player').hidden = true;
  $('keysModal').hidden = true;
  document.title = 'Kitbag Video Player';
  P = null;
  cues = [];
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  closeDetail();
  loadRecents().then(renderList);
}
$('back').onclick = closePlayer;
window.addEventListener('popstate', () => {
  if (!new URLSearchParams(location.search).has('play')) hidePlayer();
});

function save(force, beacon = false) {
  if (!P) return;
  const now = Date.now();
  if (!force && now - lastSave < 4000) return;
  lastSave = now;
  const c = cur();
  const stored = (cfg.rememberPosition && c > 15 && c < P.dur - 30) ? c : 0;
  store.set('pos:' + P.path, stored);
  const payload = JSON.stringify({ path: P.path, position: c, duration: P.dur });
  if (beacon && navigator.sendBeacon) {
    navigator.sendBeacon('/api/progress', new Blob([payload], { type: 'application/json' }));
  } else {
    fetch('/api/progress', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload }).catch(() => {});
  }
}

v.onplay = v.onpause = () => { $('ppIc').setAttribute('href', v.paused ? '#i-play' : '#i-pause'); wake(); };
v.onwaiting = v.onloadstart = () => { $('spin').hidden = false; };
v.onplaying = v.oncanplay = v.onloadeddata = () => { $('spin').hidden = true; };
v.onended = () => { $('ppIc').setAttribute('href', '#i-play'); save(true); wake(); };
v.onerror = () => { if (!P) return; $('spin').hidden = true; showErr('Playback failed. Make sure FFmpeg is installed and this file is readable.'); };
v.onvolumechange = paintVol;
v.ontimeupdate = () => {
  if (!P) return;
  const c = cur();
  paintTime(c);
  save(false);
  const adj = c - subOffset;
  let k = null;
  for (const x of cues) {
    if (x.s > adj) break;
    if (adj <= x.e) { k = x; break; }
  }
  const t = k ? k.t : '';
  if ($('cue').textContent !== t) $('cue').textContent = t;
};
v.onprogress = () => P && paintTime(cur());

const closeDetail = () => { $('detail').hidden = true; document.querySelectorAll('.row.sel').forEach((x) => x.classList.remove('sel')); };
$('x').onclick = closeDetail;
$('detail').onclick = (e) => { if (e.target === $('detail')) closeDetail(); };
$('keysBtn').onclick = () => { $('keysModal').hidden = !$('keysModal').hidden; };
$('keysClose').onclick = () => { $('keysModal').hidden = true; };
$('keysModal').onclick = (e) => { if (e.target === $('keysModal')) $('keysModal').hidden = true; };

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && $('player').hidden && !$('detail').hidden) closeDetail();
});
document.addEventListener('keydown', (e) => {
  if ($('player').hidden || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.target.tagName === 'SELECT' && e.key !== 'Escape') return;
  const k = e.key;
  let used = true;
  if (k === ' ' || k === 'k' || k === 'K') toggle();
  else if (k === 'ArrowLeft') jump(e.shiftKey ? -30 : -(cfg.skipSeconds || 10));
  else if (k === 'ArrowRight') jump(e.shiftKey ? 30 : (cfg.skipSeconds || 10));
  else if (k === 'ArrowUp') { v.muted = false; v.volume = Math.min(1, v.volume + 0.05); store.set('vol', v.volume); hud('#i-vol', `${Math.round(v.volume * 100)}%`); }
  else if (k === 'ArrowDown') { v.volume = Math.max(0, v.volume - 0.05); store.set('vol', v.volume); hud(v.volume === 0 ? '#i-mute' : '#i-vol', `${Math.round(v.volume * 100)}%`); }
  else if (k === 'f' || k === 'F') $('fs').click();
  else if (k === 'm' || k === 'M') $('mute').click();
  else if (k === 'p' || k === 'P') { if (!$('pip').hidden) $('pip').click(); }
  else if (k === 'c' || k === 'C') {
    if ($('psub').value !== 'no') { lastSubChoice = $('psub').value; $('psub').value = 'no'; setSub().then(syncUrl); hud('#i-sliders', 'Subtitles Off'); }
    else if (lastSubChoice !== 'no') { $('psub').value = lastSubChoice; setSub().then(syncUrl); hud('#i-sliders', 'Subtitles On'); }
  }
  else if (k === 'g' || k === 'G') { if ($('psub').value !== 'no') nudgeSub(-0.5); }
  else if (k === 'h' || k === 'H') { if ($('psub').value !== 'no') nudgeSub(0.5); }
  else if (k === '?') $('keysModal').hidden = !$('keysModal').hidden;
  else if (k >= '0' && k <= '9' && dur() > 0) { load((Number(k) / 10) * dur(), !v.paused); hud('#i-fwd', `${Number(k) * 10}%`); }
  else if (k === 'Escape') {
    if (!$('keysModal').hidden) $('keysModal').hidden = true;
    else if (!document.fullscreenElement) closePlayer();
  }
  else used = false;
  if (used) { e.preventDefault(); $('vol').value = v.volume; wake(); }
});

function wake() {
  const p = $('player');
  p.classList.remove('idle');
  clearTimeout(idleT);
  if (!v.paused && !dragging && $('keysModal').hidden) {
    idleT = setTimeout(() => p.classList.add('idle'), 2600);
  }
}
$('player').onmousemove = wake;
$('player').onmousedown = wake;
window.addEventListener('beforeunload', () => save(true, true));

/* ---------------- Server Heartbeat + Live Settings Sync ---------------- */
const CID = Math.random().toString(36).slice(2);
async function ping() {
  try {
    const res = await api('/api/ping?id=' + CID);
    if (res && res.configVersion && res.configVersion !== cfg.configVersion) {
      const fresh = await api('/api/config');
      applyConfig(fresh);
    }
  } catch {}
}
ping();
setInterval(ping, 2500);
window.addEventListener('pagehide', () => {
  save(true, true);
  navigator.sendBeacon('/api/bye?id=' + CID);
});
window.addEventListener('pageshow', (e) => { if (e.persisted) ping(); });

/* ---------------- Boot ---------------- */
(async () => {
  try {
    const initialCfg = await api('/api/config');
    applyConfig(initialCfg);
  } catch {
    applyConfig(cfg);
  }
  ping();
  await loadRecents();

  const qs = new URLSearchParams(location.search);
  const play = qs.get('play');
  const f = play || qs.get('file');
  if (!f) {
    await ls();
    return;
  }
  if (!play) history.replaceState(null, '', '/');
  const d = await ls(f);
  if (!play || !d || !d.file || !probed) return;
  for (const [k, id] of [['a', 'audio'], ['s', 'sub'], ['q', 'qual']]) {
    const val = qs.get(k);
    if (val == null) continue;
    if ([...$(id).options].some((o) => o.value === val)) $(id).value = val;
  }
  start(savedPosition(d.file, probed.duration));
})();
</script>
</body>
</html>
"""#
}
