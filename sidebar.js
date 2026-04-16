/* ============================================================
   sidebar.js — Solvenin ERP Shared Sidebar
   Tüm sayfalarda tek kaynak. Değiştirmek için sadece bu dosya.
   ============================================================ */

(function () {

  /* ── CSS ─────────────────────────────────────────────────── */
  const CSS = `
    :root {
      --sidebar-w: 220px;
      --sb-bg:       #1a2744;
      --sb-accent:   #38bdf8;
      --sb-accent2:  #0ea5e9;
      --font-display: 'Outfit', sans-serif;
    }
    .sidebar {
      width: var(--sidebar-w); background: var(--sb-bg);
      height: 100vh; position: fixed; top: 0; left: 0;
      display: flex; flex-direction: column; z-index: 50;
      overflow: hidden;
    }
    .sidebar-logo {
      padding: 18px 14px 14px;
      border-bottom: 1px solid rgba(255,255,255,0.08);
      text-decoration: none; display: block; overflow: hidden;
    }
    .sidebar-logo .wordmark {
      font-family: var(--font-display); font-size: 24px;
      font-weight: 800; color: #fff; letter-spacing: -1px;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block;
    }
    .sidebar-logo .dot { color: var(--sb-accent); }
    .sidebar-logo .underline {
      height: 3px; width: 72%; margin-top: 5px;
      background: linear-gradient(90deg, var(--sb-accent), var(--sb-accent2), transparent);
      border-radius: 99px;
    }
    .sidebar-sections { flex: 1; overflow-y: auto; padding: 6px 0; }
    /* Module visibility flash prevention is handled in JS via baked-hidden
       inline styles in buildHTML — no CSS race possible. */
    .sidebar-section { padding: 8px 8px 4px; }
    .sidebar-section-label {
      font-size: 9px; font-weight: 700; letter-spacing: 2px;
      text-transform: uppercase; color: rgba(148,163,184,0.7);
      padding: 0 8px; margin-bottom: 4px;
    }

    /* ── Regular nav item ── */
    .nav-item {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; border-radius: 8px; cursor: pointer;
      transition: all .15s; margin-bottom: 1px;
      text-decoration: none; color: rgba(255,255,255,0.85);
      font-size: 12px; font-weight: 500;
      border-left: 3px solid transparent;
    }
    .nav-item:hover { background: rgba(255,255,255,0.06); color: #f1f5f9; }
    .nav-item.active {
      background: rgba(56,189,248,0.12); color: #f1f5f9; font-weight: 600;
      border-left-color: var(--sb-accent);
    }
    .nav-item.active .nav-icon { color: var(--sb-accent); }
    .nav-icon { font-size: 13px; width: 16px; text-align: center; flex-shrink: 0; }
    .nav-badge {
      margin-left: auto; background: rgba(56,189,248,0.15);
      color: var(--sb-accent); font-size: 10px; font-weight: 700;
      padding: 2px 7px; border-radius: 99px;
    }

    /* ── Accordion parent ── */
    .nav-parent {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; border-radius: 8px; cursor: pointer;
      transition: all .15s; margin-bottom: 1px;
      color: rgba(255,255,255,0.85); font-size: 12px; font-weight: 500;
      user-select: none; border-left: 3px solid transparent;
    }
    .nav-parent:hover { background: rgba(255,255,255,0.06); color: #f1f5f9; }
    .nav-parent.open { color: #fff; }
    .nav-parent.has-active { color: #fff; border-left-color: var(--sb-accent); }
    .nav-parent.has-active .nav-icon { color: var(--sb-accent); }
    .nav-parent-label { flex: 1; }
    .nav-arrow {
      font-size: 8px; color: rgba(255,255,255,0.35);
      transition: transform .22s ease; flex-shrink: 0; display: inline-block;
    }
    .nav-parent.open .nav-arrow { transform: rotate(90deg); }

    /* ── Accordion children ── */
    .nav-children {
      overflow: hidden; max-height: 0;
      transition: max-height .25s ease;
    }
    .nav-children.open { max-height: 320px; }
    .nav-child {
      display: flex; align-items: center; gap: 8px;
      padding: 6px 8px 6px 30px; border-radius: 7px;
      transition: all .15s; margin-bottom: 1px;
      text-decoration: none; color: rgba(255,255,255,0.6);
      font-size: 11.5px; font-weight: 400;
    }
    .nav-child:hover { background: rgba(255,255,255,0.06); color: rgba(255,255,255,0.9); }
    .nav-child.active {
      background: rgba(56,189,248,0.1); color: var(--sb-accent); font-weight: 600;
    }
    .nav-child-dot {
      width: 4px; height: 4px; border-radius: 50%;
      background: rgba(255,255,255,0.25); flex-shrink: 0;
    }
    .nav-child.active .nav-child-dot { background: var(--sb-accent); }

    /* ── Confirm modal ── */
    #solvenin-confirm-overlay {
      display:none; position:fixed; inset:0; background:rgba(0,0,0,0.5);
      z-index:9999; align-items:center; justify-content:center;
    }
    #solvenin-confirm-overlay.open { display:flex; }
    #solvenin-confirm-box {
      background:#fff; border-radius:16px; padding:28px 32px; max-width:400px;
      width:90%; box-shadow:0 20px 60px rgba(0,0,0,0.2);
    }
    #solvenin-confirm-title { font-size:16px; font-weight:700; color:#1a1a2e; margin-bottom:8px; font-family:'Outfit',sans-serif; }
    #solvenin-confirm-msg { font-size:14px; color:#6b6560; margin-bottom:24px; line-height:1.5; }
    #solvenin-confirm-btns { display:flex; gap:10px; justify-content:flex-end; }
    #solvenin-confirm-btns button {
      padding:8px 20px; border-radius:8px; border:none; font-size:14px;
      font-weight:600; cursor:pointer; transition:all .15s;
    }
    #solvenin-confirm-cancel { background:#f3f0eb; color:#6b6560; }
    #solvenin-confirm-ok { background:#ef4444; color:#fff; }
    #solvenin-confirm-ok:hover { background:#dc2626; }

    /* ── Sidebar footer ── */
    .sidebar-footer { padding: 10px; border-top: 1px solid rgba(255,255,255,0.08); flex-shrink: 0; }
    .sidebar-user-bar {
      display: flex; align-items: stretch; gap: 4px;
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 10px; padding: 8px 10px;
      transition: background .15s;
    }
    .sidebar-user-bar:hover { background: rgba(255,255,255,0.08); }
    .sidebar-user-bar-content { flex: 1; cursor: pointer; min-width: 0; }
    .sidebar-company-row { display: flex; align-items: center; gap: 6px; margin-bottom: 2px; }
    .sidebar-company-icon { font-size: 12px; opacity: .7; }
    .sidebar-company-name { font-size: 13px; font-weight: 600; color: #fff; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .sidebar-company-chevron { font-size: 11px; color: rgba(255,255,255,0.5); }
    .sidebar-user-row { display: flex; align-items: center; gap: 6px; }
    .sidebar-user-icon { font-size: 11px; opacity: .6; }
    .sidebar-user-name { font-size: 11px; color: rgba(255,255,255,0.7); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .sidebar-logout {
      background: none; border: none; color: rgba(255,255,255,0.5);
      cursor: pointer; padding: 0 6px;
      display: flex; align-items: center; justify-content: center;
      transition: color .15s;
    }
    .sidebar-logout:hover { color: #ef4444; }
    .sidebar-logout svg { display: block; }
    .company-switcher {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; margin: 0 0 4px;
      border-radius: 8px; cursor: pointer;
      background: rgba(255,255,255,0.07);
      border: 1px solid rgba(255,255,255,0.1);
      transition: background .15s;
    }
    .company-switcher:hover { background: rgba(56,189,248,0.1); }
    .company-icon {
      font-size: 13px; flex-shrink: 0;
      width: 28px; height: 28px;
      display: flex; align-items: center; justify-content: center;
      border-radius: 6px; overflow: hidden;
      background: rgba(255,255,255,0.06);
    }
    .company-icon img { width: 100%; height: 100%; object-fit: contain; display: block; background: #fff; padding: 2px; box-sizing: border-box; }
    .company-info { flex: 1; min-width: 0; }
    .company-name {
      font-size: 11px; font-weight: 700; color: #fff;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .company-plan { font-size: 10px; color: rgba(255,255,255,0.4); text-transform: uppercase; letter-spacing: .5px; }
    .company-chevron { color: rgba(255,255,255,0.4); font-size: 13px; flex-shrink: 0; }
    .company-menu {
      position: fixed; bottom: auto; left: 10px;
      width: 200px; border-radius: 10px;
      background: #fff;
      border: 1px solid #e8e4dc;
      box-shadow: 0 8px 24px rgba(0,0,0,0.25);
      overflow: hidden; z-index: 9999;
    }
    .company-menu-item {
      display: flex; align-items: center; gap: 10px;
      padding: 8px 12px; cursor: pointer; transition: background .15s;
    }
    .company-menu-item:hover { background: #f8f7f4; }
    .company-menu-item.active { background: rgba(30,64,175,0.07); }
    .company-menu-item .c-dot {
      width: 7px; height: 7px; border-radius: 50%;
      background: #d1cdc4; flex-shrink: 0;
    }
    .company-menu-item.active .c-dot { background: #1e40af; }
    .company-menu-item .c-label {
      font-size: 12px; font-weight: 600; color: #1a1a2e;
      flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .company-menu-item .c-role { font-size: 10px; color: #a09890; }
    .company-menu-footer { border-top: 1px solid #f3f0eb; padding: 6px; }
    .company-menu-footer button {
      width: 100%; padding: 7px; border-radius: 7px;
      border: 1px dashed #d1cdc4; background: none; color: #6b6560;
      font-size: 11px; cursor: pointer; transition: all .15s;
    }
    .company-menu-footer button:hover { background: rgba(30,64,175,0.07); color: #1e40af; border-color: #1e40af; }

    /* ── User card ── */
    .user-card {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; border-radius: 8px; cursor: pointer; transition: all .15s;
    }
    .user-card:hover { background: rgba(255,255,255,0.08); }
    .user-avatar {
      width: 30px; height: 30px; border-radius: 8px;
      background: rgba(56,189,248,0.25);
      display: flex; align-items: center; justify-content: center;
      font-weight: 700; color: #fff; font-size: 12px; flex-shrink: 0;
    }
    .user-name { font-size: 11px; font-weight: 600; color: #fff; }
    .user-plan { font-size: 10px; color: rgba(255,255,255,0.4); margin-top: 1px; }
    .user-menu-btn { margin-left: auto; color: rgba(255,255,255,0.25); font-size: 16px; }

    /* ── AI Button (injected into topbar-actions) ── */
    #topbar-ai-btn {
      display: none;
      align-items: center;
      justify-content: center;
      gap: 6px;
      padding: 0 12px;
      height: 36px;
      border-radius: 8px;
      border: 1px solid transparent;
      background: linear-gradient(135deg, #1e3a8a 0%, #38bdf8 100%);
      color: #fff;
      font-size: 12px;
      font-weight: 700;
      font-family: 'DM Sans', system-ui, sans-serif;
      cursor: pointer;
      transition: transform .1s, box-shadow .15s;
      box-shadow: 0 2px 8px rgba(56,189,248,0.3);
    }
    #topbar-ai-btn.visible { display: inline-flex; }
    #topbar-ai-btn:hover { transform: translateY(-1px); box-shadow: 0 4px 14px rgba(56,189,248,0.45); }
    #topbar-ai-btn:active { transform: translateY(0); }
    #topbar-ai-btn .ai-icon { font-size: 14px; }
    @media (max-width: 640px) {
      #topbar-ai-btn .ai-label { display: none; }
      #topbar-ai-btn { padding: 0 10px; }
    }

    /* ── AI Chat Panel ── */
    #ai-chat-panel {
      position: fixed; right: 16px; bottom: 16px;
      width: 360px; height: 520px;
      background: #fff; border-radius: 16px;
      box-shadow: 0 24px 80px rgba(0,0,0,0.2), 0 0 0 1px rgba(0,0,0,0.06);
      z-index: 2000; display: none; flex-direction: column;
      overflow: hidden; font-family: 'Outfit', system-ui, sans-serif;
      transition: opacity .2s, transform .2s;
    }
    #ai-chat-panel.open { display: flex; }
    .ai-chat-header {
      background: linear-gradient(135deg, #1e40af 0%, #1a2744 100%);
      padding: 14px 16px; display: flex; align-items: center; gap: 10px; flex-shrink: 0;
    }
    .ai-chat-header-icon { font-size: 20px; }
    .ai-chat-header-title { flex: 1; }
    .ai-chat-header-title strong { display: block; color: #fff; font-size: 13px; font-weight: 700; }
    .ai-chat-header-title span { font-size: 11px; color: rgba(255,255,255,0.45); }
    .ai-chat-close {
      width: 28px; height: 28px; border-radius: 8px;
      background: rgba(255,255,255,0.1); border: none;
      color: rgba(255,255,255,0.7); font-size: 15px; cursor: pointer;
      display: flex; align-items: center; justify-content: center; transition: background .15s;
    }
    .ai-chat-close:hover { background: rgba(255,255,255,0.2); color: #fff; }
    .ai-chat-messages {
      flex: 1; overflow-y: auto; padding: 14px;
      display: flex; flex-direction: column; gap: 10px; background: #f9f8f6;
    }
    .ai-msg {
      max-width: 85%; padding: 10px 13px; border-radius: 12px;
      font-size: 13px; line-height: 1.55; word-break: break-word;
    }
    .ai-msg-user {
      background: #1e40af; color: #fff;
      align-self: flex-end; border-bottom-right-radius: 4px;
    }
    .ai-msg-assistant {
      background: #fff; color: #1a1a2e;
      align-self: flex-start; border-bottom-left-radius: 4px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.08);
    }
    .ai-msg-system {
      background: rgba(56,189,248,0.1); color: #0369a1;
      border: 1px solid rgba(56,189,248,0.3); border-radius: 8px;
      font-size: 11.5px; align-self: center; text-align: center; max-width: 90%;
    }
    #ai-support-container {
      display: none; padding: 8px 14px; background: #e0f2fe;
      border-top: 1px solid #bae6fd; justify-content: center; flex-shrink: 0;
    }
    .ai-support-btn {
      padding: 7px 16px; border-radius: 8px;
      background: #38bdf8; color: #fff; border: none;
      font-size: 12px; font-weight: 600; cursor: pointer; transition: background .15s;
    }
    .ai-support-btn:hover { background: #0ea5e9; }
    .ai-chat-footer {
      padding: 10px 12px; background: #fff;
      border-top: 1px solid #f0ece4; flex-shrink: 0;
    }
    .ai-chat-footer-meta { font-size: 10px; color: #b0a898; text-align: right; margin-bottom: 6px; }
    .ai-chat-input-row { display: flex; gap: 8px; align-items: flex-end; }
    #ai-chat-input {
      flex: 1; padding: 9px 12px; border-radius: 10px;
      border: 1.5px solid #e8e4dc; font-size: 13px;
      font-family: inherit; resize: none; outline: none;
      min-height: 38px; max-height: 120px; line-height: 1.4;
      transition: border .15s; background: #fafaf8; overflow-y: auto;
    }
    #ai-chat-input:focus { border-color: #1e40af; box-shadow: 0 0 0 3px rgba(30,64,175,0.08); }
    #ai-send-btn {
      padding: 0 14px; border-radius: 10px; height: 38px;
      background: #1e40af; color: #fff; border: none;
      font-size: 13px; font-weight: 600; cursor: pointer;
      transition: all .15s; white-space: nowrap; flex-shrink: 0;
    }
    #ai-send-btn:hover:not(:disabled) { background: #1a2744; }
    #ai-send-btn:disabled { opacity: 0.5; cursor: not-allowed; }
    .ai-mic-btn {
      background: none; border: none; font-size: 18px; cursor: pointer;
      padding: 0 4px; height: 38px; line-height: 38px; flex-shrink: 0;
      border-radius: 50%; transition: background .2s, color .2s;
    }
    .ai-mic-btn:hover { background: rgba(0,0,0,0.08); }
    .ai-mic-btn.recording { color: #dc2626; animation: ai-pulse 1s infinite; }
    @keyframes ai-pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
    .ai-speak-btn {
      background: none; border: none; font-size: 14px; cursor: pointer;
      opacity: 0.5; padding: 2px 6px; border-radius: 4px; transition: opacity .2s;
      margin-top: 2px; align-self: flex-start;
    }
    .ai-speak-btn:hover { opacity: 1; }
    .ai-speak-btn.speaking { opacity: 1; color: #2563eb; animation: ai-pulse 1s infinite; }
    .ai-msg-wrap { display: flex; flex-direction: column; align-items: flex-start; gap: 2px; max-width: 85%; }
    .ai-msg-wrap.ai-wrap-user { align-items: flex-end; align-self: flex-end; }
    .ai-msg-wrap.ai-wrap-assistant { align-self: flex-start; }
    .ai-msg-wrap.ai-wrap-system { align-self: center; }
    .ai-msg-wrap .ai-msg { max-width: 100%; }
    .ai-autospeak-toggle {
      display: flex; align-items: center; gap: 6px; margin-right: 6px; cursor: pointer;
      color: rgba(255,255,255,0.6); font-size: 11px; transition: color .15s;
    }
    .ai-autospeak-toggle:hover { color: rgba(255,255,255,0.9); }
    .ai-autospeak-toggle input { accent-color: #38bdf8; width: 14px; height: 14px; cursor: pointer; }

    /* ── New company modal ── */
    .new-company-modal {
      display: none; position: fixed; inset: 0;
      background: rgba(10,46,32,0.5); z-index: 9999;
      align-items: center; justify-content: center;
    }
    .new-company-modal.open { display: flex; }
    .new-company-box {
      background: #fff; border-radius: 16px;
      padding: 28px; width: 380px; box-shadow: 0 20px 60px rgba(0,0,0,0.2);
    }
    .new-company-box h3 { font-size: 18px; font-weight: 700; color: #1a1a2e; margin-bottom: 6px; font-family:'Outfit',sans-serif; }
    .new-company-box p { font-size: 13px; color: #6b6560; margin-bottom: 20px; }
    .new-company-box input {
      width: 100%; padding: 10px 12px; border-radius: 8px;
      border: 1.5px solid #e8e4dc; font-size: 14px; margin-bottom: 16px;
      outline: none; transition: border .15s;
    }
    .new-company-box input:focus, .new-company-box select:focus { border-color: #1e40af; box-shadow: 0 0 0 3px rgba(30,64,175,0.1); }
    .new-company-box select {
      width: 100%; padding: 10px 12px; border: 1.5px solid #e0dcd7; border-radius: 10px;
      font-size: 14px; margin-bottom: 14px; background: #fff; color: #1a1a2e; outline: none;
    }
    .new-company-box .btn-row { display: flex; gap: 10px; justify-content: flex-end; }
    .new-company-box .btn-cancel {
      padding: 8px 18px; border-radius: 8px; border: 1.5px solid #e8e4dc;
      background: none; color: #6b6560; font-size: 13px; cursor: pointer;
    }
    .new-company-box .btn-create {
      padding: 8px 18px; border-radius: 8px; border: none;
      background: #1e40af; color: #fff; font-size: 13px;
      font-weight: 600; cursor: pointer; transition: background .15s;
    }
    .new-company-box .btn-create:hover { background: #1a2744; }
    .new-company-box .btn-create:disabled { opacity:.6; cursor:not-allowed; }
    @keyframes spin { to { transform:rotate(360deg); } }

    /* ── MOBILE ── */
    .sb-hamburger {
      display: none; position: fixed; top: 10px; left: 10px; z-index: 100;
      width: 36px; height: 36px; border-radius: 8px;
      background: var(--sb-bg); border: none; cursor: pointer;
      align-items: center; justify-content: center;
      box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    }
    .sb-hamburger span {
      display: block; width: 16px; height: 2px; background: #fff;
      border-radius: 2px; position: relative; transition: all .2s;
    }
    .sb-hamburger span::before, .sb-hamburger span::after {
      content: ''; position: absolute; left: 0; width: 16px; height: 2px;
      background: #fff; border-radius: 2px; transition: all .2s;
    }
    .sb-hamburger span::before { top: -5px; }
    .sb-hamburger span::after { top: 5px; }
    .sb-hamburger.open span { background: transparent; }
    .sb-hamburger.open span::before { top: 0; transform: rotate(45deg); }
    .sb-hamburger.open span::after { top: 0; transform: rotate(-45deg); }
    .sb-overlay {
      display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.45);
      z-index: 54; backdrop-filter: blur(2px);
    }
    .sb-overlay.open { display: block; }
    @media (max-width: 768px) {
      .sb-hamburger { display: flex; }
      .sidebar {
        width: 260px;
        transform: translateX(-100%);
        transition: transform .25s ease;
        z-index: 55;
      }
      .sidebar.sb-open { transform: translateX(0); }
      .main { margin-left: 0 !important; width: 100% !important; }
      .topbar { padding-left: 52px !important; }
    }
  `;

  /* ── CURRENCY ────────────────────────────────────────────── */
  const CURRENCY_SYMBOLS = {
    'USD':'$','EUR':'€','GBP':'£','TRY':'₺','JPY':'¥','CNY':'¥',
    'KRW':'₩','INR':'₹','RUB':'₽','BRL':'R$','CAD':'C$','AUD':'A$',
    'CHF':'Fr','SEK':'kr','NOK':'kr','DKK':'kr','PLN':'zł','CZK':'Kč',
    'HUF':'Ft','RON':'lei','BGN':'лв','HRK':'kn','ISK':'kr','MXN':'$',
    'ARS':'$','CLP':'$','COP':'$','PEN':'S/.','UYU':'$','VEF':'Bs',
    'SAR':'﷼','AED':'د.إ','QAR':'﷼','KWD':'د.ك','BHD':'BD','OMR':'﷼',
    'EGP':'£','ZAR':'R','NGN':'₦','KES':'KSh','GHS':'₵','MAD':'MAD',
    'UAH':'₴','KZT':'₸','UZS':'so\'m','AZN':'₼','GEL':'₾','AMD':'֏',
  };

  window.getBaseCurrency = function() {
    return localStorage.getItem('baseCurrency') || 'USD';
  };

  window.getCurrencySymbol = function(code) {
    return CURRENCY_SYMBOLS[code || window.getBaseCurrency()] || (code || '$');
  };

  window.fmtMoney = function(amount, code) {
    const sym = window.getCurrencySymbol(code);
    const num = parseFloat(amount) || 0;
    return sym + num.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2});
  };

  window.fmtMoneyShort = function(amount, code) {
    const sym = window.getCurrencySymbol(code);
    const num = parseFloat(amount) || 0;
    if (num >= 1000000) return sym + (num/1000000).toFixed(1) + 'M';
    if (num >= 1000) return sym + (num/1000).toFixed(1) + 'K';
    return sym + num.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2});
  };

  /* ── NAV ITEMS ───────────────────────────────────────────── */
  // children[] → accordion sub-items; no children → direct link
  const NAV = [
    {
      labelKey: 'nav_group_main',
      items: [
        {
          icon: '📦', key: 'nav_inventory', href: 'inventory.html',
          children: [
            { key: 'nav_products',        href: 'inventory.html' },
            { key: 'nav_stock_movements', href: 'inventory.html#movements' },
            { key: 'nav_stockcount',      href: 'stockcount.html' },
            { key: 'nav_warehouses',      href: 'settings.html#warehouses' },
            { key: 'nav_reports',         href: 'reports-stock.html' },
          ]
        },
        {
          icon: '👤', key: 'nav_contacts', href: 'contacts.html',
          children: [
            { key: 'nav_contacts',  href: 'contacts.html' },
            { key: 'nav_reports',   href: 'reports-contacts.html' },
          ]
        },
        {
          icon: '🎯', key: 'nav_crm', href: 'crm.html',
          children: [
            { key: 'nav_crm',     href: 'crm.html' },
            { key: 'nav_reports', href: 'reports-crm.html' },
          ]
        },
        { icon: '🖥️', key: 'nav_pos', href: 'pos.html' },
        {
          icon: '💰', key: 'nav_sales', href: 'sales.html',
          children: [
            { key: 'nav_sales_orders',   href: 'sales.html?view=orders' },
            { key: 'nav_sales_invoices', href: 'sales.html?view=invoices' },
            { key: 'nav_payments',       href: 'sales.html#payments' },
            { key: 'nav_reports',        href: 'reports-sales.html' },
          ]
        },
        {
          icon: '🛒', key: 'nav_purchasing', href: 'purchasing.html',
          children: [
            { key: 'nav_purchase_orders',   href: 'purchasing.html?view=orders' },
            { key: 'nav_purchase_invoices', href: 'purchasing.html?view=invoices' },
            { key: 'nav_reports',           href: 'reports-purchase.html' },
          ]
        },
        { icon: '🏭', key: 'nav_production', href: 'production.html',
          children: [
            { key: 'nav_production', href: 'production.html' },
            { key: 'nav_labels',     href: 'labels.html' },
          ]
        },
      ]
    },
    {
      labelKey: 'nav_group_finance',
      items: [
        {
          icon: '💳', key: 'nav_finance', href: null,
          children: [
            { key: 'nav_cashbank',        href: 'cashbank.html' },
            { key: 'nav_cashier_report',  href: 'cashbank.html?tab=cashier-report' },
            { key: 'nav_reports',         href: 'reports-finance.html' },
          ]
        },
        {
          icon: '📊', key: 'nav_accounting', href: 'accounting.html',
          children: [
            { key: 'nav_accounting', href: 'accounting.html' },
            { key: 'nav_reports',    href: 'reports-accounting.html' },
          ]
        },
      ]
    },
    {
      labelKey: 'nav_group_management',
      items: [
        {
          icon: '👥', key: 'nav_hr', href: 'hr.html',
          children: [
            { key: 'nav_employees',  href: 'hr.html' },
            { key: 'nav_payroll',    href: 'hr.html#payroll' },
            { key: 'nav_leave',      href: 'hr.html#leaves' },
            { key: 'nav_attendance', href: 'hr.html#attendance' },
            { key: 'nav_reports',    href: 'reports-hr.html' },
          ]
        },
        { icon: '🚚', key: 'nav_shipping',    href: 'shipping.html' },
        { icon: '📅', key: 'nav_projects',    href: 'projects.html' },
        { icon: '🔧', key: 'nav_maintenance', href: 'maintenance.html' },
      ]
    },
    {
      labelKey: 'nav_group_system',
      items: [
        { icon: '⚙️', key: 'nav_settings',     href: 'settings.html',     alwaysVisible: true },
        { icon: '💎', key: 'nav_subscription', href: 'subscription.html', alwaysVisible: true },
      ]
    },
  ];

  /* ── ACCORDION STATE ─────────────────────────────────────── */
  // Manually toggled groups (persists across language re-renders)
  const _manualOpen = new Set();

  function hrefBase(href) {
    return href ? href.split('#')[0] : href;
  }

  function isGroupOpen(key, page) {
    if (_manualOpen.has(key)) return true;
    // Auto-open if any child page is active
    const section = NAV.flatMap(s => s.items).find(i => i.key === key);
    if (!section || !section.children) return false;
    return section.children.some(c => c.href && c.href !== '#' && page === hrefBase(c.href));
  }

  /* ── HELPERS ─────────────────────────────────────────────── */
  function currentPage() {
    return window.location.pathname.split('/').pop() || 'dashboard.html';
  }

  function injectCSS() {
    if (document.getElementById('solvenin-sidebar-css')) return;
    const style = document.createElement('style');
    style.id = 'solvenin-sidebar-css';
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  /* ── MODULE VISIBILITY (cache + filter approach) ─────────
     The sidebar is rendered ONCE with the correct set of items.
     No bake-hide / no reveal pass. State flow:
       1. On script load, read cached enabled-modules from localStorage
          (per-company). If present, use it to filter NAV immediately —
          zero flash on subsequent visits.
       2. loadSidebarData() fetches company_modules + user permissions,
          merges them into the enabled set, and if the set differs from
          the cached value, re-renders the sidebar in place.
       3. First-ever visit (no cache): render ONLY alwaysVisible items
          (Settings/Plans). After fetch, full sidebar renders. A brief
          minimal sidebar is better than a flash of disabled items.
  */
  const MODULE_NAV_MAP = {
    inventory:   ['nav_inventory'],
    sales:       ['nav_sales'],
    purchasing:  ['nav_purchasing'],
    contacts:    ['nav_contacts', 'nav_cariler'],
    finance:     ['nav_cashbank', 'nav_finance'],
    accounting:  ['nav_accounting'],
    hr:          ['nav_hr'],
    production:  ['nav_production'],
    projects:    ['nav_projects'],
    shipping:    ['nav_shipping'],
    maintenance: ['nav_maintenance'],
    crm:         ['nav_crm'],
    // reports has no top-level entry in NAV — every nav_reports child
    // inherits visibility from its parent module (Stok, Satış, ...).
    pos:         ['nav_pos'],
    restaurant:  ['nav_restaurant'],
    hotel:       ['nav_hotel'],
    clinic:      ['nav_clinic'],
    elevator:    ['nav_elevator'],
    ecommerce:   ['nav_ecommerce'],
    cash_bank:   ['nav_cashbank'], // legacy alias
  };
  if (window.ModulesConfig && window.ModulesConfig.MODULE_NAV_MAP) {
    Object.assign(MODULE_NAV_MAP, window.ModulesConfig.MODULE_NAV_MAP);
  }

  // Reverse: nav-key → module. A nav-key present here is "gated" —
  // visible only when its module is in the enabled set.
  const NAV_KEY_TO_MODULE = {};
  Object.entries(MODULE_NAV_MAP).forEach(([mod, keys]) => {
    keys.forEach(k => { NAV_KEY_TO_MODULE[k] = mod; });
  });

  // _enabledModules: Set<string> of enabled module keys, or null = "unknown"
  // null → render only alwaysVisible items (first-ever visit).
  let _enabledModules = null;
  try {
    const cid = localStorage.getItem('currentCompanyId');
    if (cid) {
      const raw = localStorage.getItem('sb_mods_' + cid);
      if (raw) {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr)) _enabledModules = new Set(arr);
      }
    }
  } catch(e) {}

  // Returns true if a gated nav-key should render with current state.
  // Ungated keys (children without a module mapping, e.g. nav_products)
  // always return true here — they inherit visibility from their parent.
  function isNavKeyAllowed(key) {
    const mod = NAV_KEY_TO_MODULE[key];
    if (!mod) return true;              // ungated child
    if (_enabledModules === null) return false; // no data yet → hide gated
    return _enabledModules.has(mod);
  }

  // Produce a filtered NAV array by removing items/children for disabled modules.
  function filteredNav() {
    const out = [];
    NAV.forEach(section => {
      const items = [];
      section.items.forEach(item => {
        if (item.alwaysVisible) { items.push(item); return; }

        if (item.children) {
          // Accordion parent — gated by its own module
          if (!isNavKeyAllowed(item.key)) return;
          // Filter children too (for cross-cutting like nav_reports)
          const kids = item.children.filter(c => isNavKeyAllowed(c.key));
          if (kids.length === 0) return;
          items.push({ ...item, children: kids });
        } else {
          if (!isNavKeyAllowed(item.key)) return;
          items.push(item);
        }
      });
      if (items.length > 0) out.push({ ...section, items });
    });
    return out;
  }

  /* ── BUILD HTML ──────────────────────────────────────────── */
  function buildHTML() {
    const page = currentPage();
    const _t = window.t || (k => k);
    let sectionsHTML = '';

    filteredNav().forEach(section => {
      let itemsHTML = section.items.map(item => {

        if (item.children) {
          // ── Accordion parent ──
          const open = isGroupOpen(item.key, page);
          const hasActive = item.children.some(c =>
            c.href && c.href !== '#' && page === hrefBase(c.href)
          );
          const parentClasses = [
            'nav-parent',
            open ? 'open' : '',
            hasActive ? 'has-active' : ''
          ].filter(Boolean).join(' ');

          const childrenHTML = item.children.map(child => {
            const childBase = hrefBase(child.href);
            const childHash = child.href && child.href.includes('#') ? '#' + child.href.split('#')[1] : null;
            const active = child.href && child.href !== '#' && page === childBase &&
              (!childHash || window.location.hash === childHash);
            const label = _t(child.key) || child.key;
            return `<a class="nav-child${active ? ' active' : ''}" data-key="${child.key}" href="${child.href || '#'}">
              <span class="nav-child-dot"></span>${label}
            </a>`;
          }).join('');

          const label = _t(item.key) || item.key;
          return `
            <div class="${parentClasses}" data-key="${item.key}" onclick="sidebarToggleAccordion('${item.key}')">
              <span class="nav-icon">${item.icon}</span>
              <span class="nav-parent-label">${label}</span>
              <span class="nav-arrow">▶</span>
            </div>
            <div class="nav-children${open ? ' open' : ''}" data-key="${item.key}">
              ${childrenHTML}
            </div>`;

        } else {
          // ── Regular standalone nav item ──
          const active = item.href && item.href !== '#' && page === item.href;
          const label = _t(item.key) || item.key;
          return `<a class="nav-item${active ? ' active' : ''}" data-key="${item.key}" href="${item.href || '#'}">
            <span class="nav-icon">${item.icon}</span>${label}
          </a>`;
        }

      }).join('');

      const sectionLabel = _t(section.labelKey) || section.labelKey;
      sectionsHTML += `
        <div class="sidebar-section">
          <div class="sidebar-section-label">${sectionLabel}</div>
          ${itemsHTML}
        </div>`;
    });

    return `
      <a class="sidebar-logo" href="dashboard.html">
        <div class="wordmark">solvenin<span class="dot">.</span></div>
        <div class="underline"></div>
      </a>
      <div class="sidebar-sections">${sectionsHTML}</div>
      <div class="sidebar-footer">
        <div class="company-menu" id="sb-company-menu" style="display:none">
          <div class="company-menu-list" id="sb-company-menu-list"></div>
          <div class="company-menu-footer" id="sb-company-menu-footer"></div>
        </div>
        <div class="sidebar-user-bar" id="sidebar-user-bar">
          <div class="sidebar-user-bar-content" onclick="sidebarToggleCompanyMenu()">
            <div class="sidebar-company-row">
              <span class="sidebar-company-icon">🏢</span>
              <span class="sidebar-company-name" id="sb-company-name">Loading...</span>
              <span class="sidebar-company-chevron" id="sb-company-chevron">⌄</span>
            </div>
            <div class="sidebar-user-row">
              <span class="sidebar-user-icon">👤</span>
              <span class="sidebar-user-name" id="sb-user-name">Loading...</span>
            </div>
          </div>
          <button class="sidebar-logout" id="sb-logout-btn" title="Çıkış" onclick="event.stopPropagation();sidebarLogout()"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg></button>
        </div>
      </div>

      <!-- New Company Modal -->
      <div class="new-company-modal" id="sb-new-company-modal">
        <div class="new-company-box">
          <h3>New Company</h3>
          <p>Create a new company to manage separately.</p>
          <input type="text" id="sb-new-company-name" placeholder="Company name..." />
          <select id="sb-new-company-country"><option value="">Loading...</option></select>
          <div class="btn-row">
            <button class="btn-cancel" onclick="sidebarCloseNewCompany()">Cancel</button>
            <button class="btn-create" id="sb-btn-create-company" onclick="sidebarCreateCompany()">Create</button>
          </div>
        </div>
      </div>`;
  }

  /* ── MOUNT ───────────────────────────────────────────────── */
  function mount() {
    if (!document.body) return false;
    injectCSS();

    let sidebar = document.getElementById('sidebar');
    if (!sidebar) {
      sidebar = document.createElement('aside');
      sidebar.className = 'sidebar';
      sidebar.id = 'sidebar';
      document.body.insertBefore(sidebar, document.body.firstChild);
    }
    sidebar.innerHTML = buildHTML();

    // Inject hamburger + overlay for mobile
    if (!document.getElementById('sb-hamburger')) {
      const btn = document.createElement('button');
      btn.id = 'sb-hamburger';
      btn.className = 'sb-hamburger';
      btn.innerHTML = '<span></span>';
      btn.onclick = () => {
        sidebar.classList.toggle('sb-open');
        btn.classList.toggle('open');
        document.getElementById('sb-mobile-overlay')?.classList.toggle('open');
      };
      document.body.appendChild(btn);
      const ov = document.createElement('div');
      ov.id = 'sb-mobile-overlay';
      ov.className = 'sb-overlay';
      ov.onclick = () => {
        sidebar.classList.remove('sb-open');
        btn.classList.remove('open');
        ov.classList.remove('open');
      };
      document.body.appendChild(ov);
    }

    // Close sidebar on mobile when navigating
    sidebar.addEventListener('click', (e) => {
      if (e.target.closest('a[href]') && window.innerWidth <= 768) {
        sidebar.classList.remove('sb-open');
        document.getElementById('sb-hamburger')?.classList.remove('open');
        document.getElementById('sb-mobile-overlay')?.classList.remove('open');
      }
    });

    // Inject AI chat panel if not exists
    injectAIPanel();
    injectAIFloatingButton();

    // Inject confirm modal if not exists
    if (!document.getElementById('solvenin-confirm-overlay')) {
      const overlay = document.createElement('div');
      overlay.id = 'solvenin-confirm-overlay';
      overlay.innerHTML = `
        <div id="solvenin-confirm-box">
          <div id="solvenin-confirm-title">Confirm</div>
          <div id="solvenin-confirm-msg"></div>
          <div id="solvenin-confirm-btns">
            <button id="solvenin-confirm-cancel">Cancel</button>
            <button id="solvenin-confirm-ok">Delete</button>
          </div>
        </div>`;
      document.body.appendChild(overlay);
      document.getElementById('solvenin-confirm-cancel').onclick = () => {
        overlay.classList.remove('open');
        if (window._confirmReject) window._confirmReject();
      };
    }
    return true;
  }

  /* ── SUPABASE DATA ───────────────────────────────────────── */
  function showSubBanner(msg, type) {
    if (document.getElementById('sub-banner')) return;
    const banner = document.createElement('div');
    banner.id = 'sub-banner';
    const bg = type === 'danger' ? '#fef2f2' : '#fffbeb';
    const color = type === 'danger' ? '#991b1b' : '#92400e';
    const border = type === 'danger' ? '#fecaca' : '#fde68a';
    banner.style.cssText = `position:sticky;top:0;z-index:90;background:${bg};color:${color};padding:10px 20px;font-size:13px;font-weight:500;border-bottom:1px solid ${border};text-align:center`;
    banner.innerHTML = msg;
    const main = document.querySelector('.main');
    if (main) main.insertBefore(banner, main.firstChild);
    else document.body.insertBefore(banner, document.body.firstChild);
  }

  function disableAllSaveButtons() {
    const patterns = [/save/i, /kaydet/i, /ekle/i, /yeni/i, /create/i, /submit/i, /\+\s*Yeni/i];
    const observer = new MutationObserver(() => {
      document.querySelectorAll('button, .btn, .btn-primary').forEach(btn => {
        const txt = (btn.textContent || '').trim();
        if (patterns.some(p => p.test(txt)) && !btn.dataset._spDisabled) {
          btn.dataset._spDisabled = '1';
          btn.disabled = true;
          btn.style.opacity = '0.4';
          btn.style.cursor = 'not-allowed';
          btn.title = 'Aboneliğiniz sona erdi';
        }
      });
    });
    observer.observe(document.body, { childList: true, subtree: true });
    // Run once immediately
    setTimeout(() => observer.takeRecords().forEach(() => {}), 100);
    document.querySelectorAll('button, .btn, .btn-primary').forEach(btn => {
      const txt = (btn.textContent || '').trim();
      if (patterns.some(p => p.test(txt))) {
        btn.disabled = true;
        btn.style.opacity = '0.4';
        btn.style.cursor = 'not-allowed';
      }
    });
  }

  // Render company logo into the sidebar's company-switcher icon slot.
  // Falls back to company initials if no logo, then to 🏢 emoji.
  function applySidebarLogo(logoUrl, companyName) {
    const slot = document.getElementById('sb-company-icon');
    if (!slot) return;
    if (logoUrl) {
      slot.innerHTML = `<img src="${logoUrl}" alt="">`;
      slot.style.background = '#fff';
    } else if (companyName) {
      const initials = companyName.trim().split(/\s+/).map(w=>w[0]).join('').slice(0,2).toUpperCase();
      slot.textContent = initials || '🏢';
      slot.style.fontWeight = '700';
      slot.style.color = '#fff';
      slot.style.background = '';
    } else {
      slot.textContent = '🏢';
      slot.style.background = '';
    }
  }
  // Expose to other pages so they can re-render after companyLogoChanged
  window.applySidebarLogo = applySidebarLogo;
  // Expose module-visibility hook so settings.html can live-update the
  // sidebar after a module toggle (no full reload required).
  window.applySidebarModules = applyModuleVisibility;

  // If the logo is already cached from a recent visit, render immediately
  // (before the async loadSidebarData fetch finishes).
  try {
    const cachedCompanyId = localStorage.getItem('currentCompanyId');
    if (cachedCompanyId) {
      const cachedLogo = localStorage.getItem('solvenin_company_logo_'+cachedCompanyId);
      if (cachedLogo) setTimeout(() => applySidebarLogo(cachedLogo, null), 0);
    }
  } catch(e) {}

  // Live update when settings page saves a new logo
  document.addEventListener('companyLogoChanged', (e) => {
    applySidebarLogo(e.detail?.logo, document.getElementById('sb-company-name')?.textContent);
  });

  async function loadSidebarData() {
    try {
      const sb = window._supabase || window.supabase;
      if (!sb || !sb.auth) return;

      const { data: { user } } = await sb.auth.getUser();
      if (!user) return;

      const email = user.email || '';
      const initials = email.substring(0, 2).toUpperCase();
      const nameEl = document.getElementById('sb-user-name');
      const avatarEl = document.getElementById('sb-user-avatar');
      if (nameEl) nameEl.textContent = email;
      if (avatarEl) avatarEl.textContent = initials;

      const companyId = localStorage.getItem('currentCompanyId');
      if (!companyId) return;

      // Fetch company info and user plan in parallel
      const [compRes, profileRes] = await Promise.all([
        sb.from('companies').select('name, base_currency, is_frozen, freeze_reason, subscription_status, subscription_end, max_users, plan, logo_url').eq('id', companyId).single(),
        sb.from('profiles').select('plan').eq('id', user.id).single()
      ]);

      // Deleted-company gate: if RLS hides this company (it's soft-deleted or
      // the user lost access), the lookup returns no rows. In that case
      // re-check the user's valid companies and either switch or block.
      if (compRes.error || !compRes.data) {
        try {
          const { data: myCompanies } = await sb.rpc('get_my_companies');
          const valid = (myCompanies || []).filter(c => c.company_id !== companyId);
          if (valid.length > 0) {
            // User has another valid company — switch silently
            console.warn('[sidebar] currentCompanyId is no longer accessible, switching to', valid[0].company_id);
            localStorage.setItem('currentCompanyId', valid[0].company_id);
            location.reload();
            return;
          }
          // No valid companies left — show the deleted-account screen
          document.body.innerHTML = `<div style="position:fixed;inset:0;background:#1a2744;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:16px;padding:40px;text-align:center;color:#fff;font-family:'DM Sans',sans-serif;z-index:99999">
            <div style="font-size:64px">🗑️</div>
            <h2 style="font-family:'Outfit',sans-serif;font-size:28px;font-weight:800">Şirket Çöp Kutusunda</h2>
            <p style="font-size:14px;color:rgba(255,255,255,.75);max-width:520px;line-height:1.6">Bu şirket silindi. 30 gün içinde geri yükleyebilirsiniz. Bu süre sonunda tüm veriler kalıcı olarak silinir.</p>
            <p style="font-size:13px;color:rgba(255,255,255,.5);margin-top:8px">Geri yüklemek için: <a href="mailto:support@solvenin.com" style="color:#38bdf8">support@solvenin.com</a></p>
            <button onclick="(async()=>{try{await window._supabase.auth.signOut()}catch(e){}localStorage.clear();location.href='auth.html'})()" style="margin-top:20px;padding:10px 24px;background:rgba(56,189,248,.2);color:#38bdf8;border:1px solid rgba(56,189,248,.3);border-radius:8px;cursor:pointer;font-size:13px;font-weight:600">Çıkış Yap</button>
          </div>`;
          return;
        } catch(e) {
          console.error('[sidebar] gate check failed:', e);
        }
      }

      // Subscription check
      if (compRes.data?.subscription_end) {
        const endDate = new Date(compRes.data.subscription_end);
        const daysLeft = Math.ceil((endDate - new Date()) / (1000*60*60*24));
        window.__subscriptionDaysLeft = daysLeft;
        window.__subscriptionStatus = compRes.data.subscription_status;
        if (daysLeft < 0) {
          // Expired — read-only mode
          showSubBanner('🔴 Aboneliğiniz sona erdi. Verileriniz korunuyor ancak yeni kayıt ekleyemezsiniz. Yenilemek için: support@solvenin.com', 'danger');
          disableAllSaveButtons();
        } else if (daysLeft <= 7) {
          showSubBanner(`⚠️ Aboneliğiniz ${daysLeft} gün içinde sona erecek.`, 'warning');
        }
      }

      // Freeze check
      if (compRes.data?.is_frozen) {
        document.body.innerHTML = `<div style="position:fixed;inset:0;background:#1a2744;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:16px;padding:40px;text-align:center;color:#fff;font-family:'DM Sans',sans-serif;z-index:99999">
          <div style="font-size:64px">🔒</div>
          <h2 style="font-family:'Outfit',sans-serif;font-size:28px;font-weight:800">Hesabınız Askıya Alınmıştır</h2>
          <p style="font-size:14px;color:rgba(255,255,255,.7);max-width:500px;line-height:1.6">${compRes.data.freeze_reason || 'Hesabınız yönetici tarafından askıya alınmıştır.'}</p>
          <p style="font-size:13px;color:rgba(255,255,255,.5);margin-top:20px">Detaylar için: <a href="mailto:support@solvenin.com" style="color:#38bdf8">support@solvenin.com</a></p>
          <button onclick="supabase.createClient('https://jaakjdzpdizjbzvbtcld.supabase.co','sb_publishable_Zp3NcrPr7yPrL8zgpiNmfA_YF7RGHe9').auth.signOut().then(()=>location.href='auth.html')" style="margin-top:20px;padding:10px 24px;background:rgba(239,68,68,.2);color:#fca5a5;border:1px solid rgba(239,68,68,.3);border-radius:8px;cursor:pointer;font-size:13px;font-weight:600">Çıkış Yap</button>
        </div>`;
        return;
      }

      const company = compRes.data;
      const userPlan = profileRes.data?.plan || 'free';
      const plan = userPlan;

      if (company) {
        const cnEl = document.getElementById('sb-company-name');
        if (cnEl) cnEl.textContent = company.name;
        if (company.base_currency) {
          localStorage.setItem('baseCurrency', company.base_currency);
          document.dispatchEvent(new CustomEvent('currencyLoaded', { detail: company.base_currency }));
        }
        // Cache logo for fast access from other pages / PDF generators
        try {
          localStorage.setItem('solvenin_company_logo_'+companyId, company.logo_url || '');
          localStorage.setItem('solvenin_company_logo_'+companyId+'_at', String(Date.now()));
        } catch(e) {}
        // Render in sidebar header
        applySidebarLogo(company.logo_url, company.name);
        document.dispatchEvent(new CustomEvent('companyLogoLoaded', { detail: { logo: company.logo_url, name: company.name } }));
      }

      const cpEl = document.getElementById('sb-company-plan');
      const upEl = document.getElementById('sb-user-plan');
      if (cpEl) cpEl.textContent = plan.toUpperCase();
      if (upEl) upEl.textContent = plan.charAt(0).toUpperCase() + plan.slice(1) + ' Plan';

      const { data: companies } = await sb.rpc('get_my_companies');
      if (companies) renderCompanyMenu(companies, companyId);

      // Module visibility (company-level)
      const { data: modules } = await sb.from('company_modules')
        .select('module, is_active')
        .eq('company_id', companyId);
      if (modules) applyModuleVisibility(modules);

      // User permission visibility (user-level)
      if (typeof window.loadAllPermissions === 'function') {
        const permMap = await window.loadAllPermissions();
        if (permMap && Object.keys(permMap).length > 0) {
          const noViewModules = [];
          for (const [mod, p] of Object.entries(permMap)) {
            if (!p.can_view) noViewModules.push({ module: mod, is_active: false });
          }
          if (noViewModules.length) applyModuleVisibility(noViewModules);
        }
      }

    } catch (e) {
      console.error('Sidebar data error:', e);
    }
  }

  // Public API for live-update from settings.html after a module toggle.
  // Defined further down — assigned at end of IIFE.

  // applyModuleVisibility — takes the raw modules array (from company_modules
  // or user_permissions), updates the enabled-set state, caches it, and
  // re-renders the sidebar if the set changed.
  function applyModuleVisibility(modules) {
    if (!Array.isArray(modules)) return;

    // Start from what we already had (so user_permissions can further
    // restrict company_modules, not add to it).
    const next = _enabledModules ? new Set(_enabledModules) : new Set();

    // If this is the first call (from company_modules), wipe and rebuild.
    // We detect it by checking if ALL passed modules are in a "known" shape
    // — company_modules passes the full list. user_permissions passes only
    // the no-view ones (always is_active:false), so we must subtract those.
    const allPassive = modules.every(m => m.is_active === false);
    if (!allPassive) {
      // company_modules → authoritative list of active modules
      next.clear();
      modules.forEach(m => { if (m.is_active) next.add(m.module); });
    } else {
      // user permission subtraction
      modules.forEach(m => next.delete(m.module));
    }

    const newArr = [...next].sort();
    _enabledModules = next;

    // Debug — inspect from devtools
    window.__sbEnabledModules = newArr;
    window.__sbNavKeyMap      = NAV_KEY_TO_MODULE;

    try {
      const cid = localStorage.getItem('currentCompanyId');
      if (cid) localStorage.setItem('sb_mods_' + cid, JSON.stringify(newArr));
    } catch(e) {}

    // Always rerender after a state update. The rerender only swaps the
    // .sidebar-sections innerHTML, which is cheap and invisible to the
    // user. Skipping it on a "no change" check turned out to be brittle
    // because the comparison can match against a hydrated stale cache.
    rerenderSidebar();
  }

  // Rebuilds ONLY the sections container so company info / user card
  // / modals in the footer aren't disturbed.
  function rerenderSidebar() {
    const sb = document.getElementById('sidebar');
    if (!sb) return;
    const container = sb.querySelector('.sidebar-sections');
    if (!container) {
      // Fallback — nuke and rebuild everything.
      sb.innerHTML = buildHTML();
      return;
    }
    // Re-render using filtered NAV
    const page = currentPage();
    const _t = window.t || (k => k);
    let html = '';
    filteredNav().forEach(section => {
      let itemsHTML = section.items.map(item => {
        if (item.children) {
          const open = isGroupOpen(item.key, page);
          const hasActive = item.children.some(c =>
            c.href && c.href !== '#' && page === hrefBase(c.href));
          const parentClasses = ['nav-parent', open ? 'open' : '', hasActive ? 'has-active' : ''].filter(Boolean).join(' ');
          const childrenHTML = item.children.map(child => {
            const childBase = hrefBase(child.href);
            const childHash = child.href && child.href.includes('#') ? '#' + child.href.split('#')[1] : null;
            const active = child.href && child.href !== '#' && page === childBase &&
              (!childHash || window.location.hash === childHash);
            const label = _t(child.key) || child.key;
            return `<a class="nav-child${active ? ' active' : ''}" data-key="${child.key}" href="${child.href || '#'}">
              <span class="nav-child-dot"></span>${label}
            </a>`;
          }).join('');
          const label = _t(item.key) || item.key;
          return `
            <div class="${parentClasses}" data-key="${item.key}" onclick="sidebarToggleAccordion('${item.key}')">
              <span class="nav-icon">${item.icon}</span>
              <span class="nav-parent-label">${label}</span>
              <span class="nav-arrow">▶</span>
            </div>
            <div class="nav-children${open ? ' open' : ''}" data-key="${item.key}">
              ${childrenHTML}
            </div>`;
        } else {
          const active = item.href && item.href !== '#' && page === item.href;
          const label = _t(item.key) || item.key;
          return `<a class="nav-item${active ? ' active' : ''}" data-key="${item.key}" href="${item.href || '#'}">
            <span class="nav-icon">${item.icon}</span>${label}
          </a>`;
        }
      }).join('');
      const sectionLabel = _t(section.labelKey) || section.labelKey;
      html += `<div class="sidebar-section"><div class="sidebar-section-label">${sectionLabel}</div>${itemsHTML}</div>`;
    });
    container.innerHTML = html;
  }

  function renderCompanyMenu(companies, currentId) {
    const list = document.getElementById('sb-company-menu-list');
    const footer = document.getElementById('sb-company-menu-footer');
    if (!list) return;

    list.innerHTML = companies.map(c => `
      <div class="company-menu-item ${c.company_id === currentId ? 'active' : ''} ${c.status === 'suspended' ? 'suspended' : ''}"
           onclick="sidebarSwitchCompany('${c.company_id}')">
        <div class="c-dot"></div>
        <div class="c-label">${c.company_name}</div>
        <div class="c-role">${c.role || ''}</div>
      </div>`).join('');

    if (footer) {
      footer.innerHTML = `<button onclick="sidebarOpenNewCompany()">+ New Company</button>`;
    }
  }

  /* ── PUBLIC FUNCTIONS ────────────────────────────────────── */
  window.sidebarToggleAccordion = function(key) {
    if (_manualOpen.has(key)) {
      _manualOpen.delete(key);
    } else {
      _manualOpen.add(key);
    }
    // Update DOM in-place (no full re-render needed)
    const page = currentPage();
    const open = isGroupOpen(key, page);
    const parentEl = document.querySelector(`.nav-parent[data-key="${key}"]`);
    const childrenEl = document.querySelector(`.nav-children[data-key="${key}"]`);
    if (parentEl) parentEl.classList.toggle('open', open);
    if (childrenEl) childrenEl.classList.toggle('open', open);
  };

  window.sidebarLogout = async function() {
    try {
      const sb = window._supabase || window.supabase;
      if (sb && sb.auth) await sb.auth.signOut();
    } catch (e) { console.warn(e); }
    localStorage.removeItem('currentCompanyId');
    window.location.href = 'auth.html';
  };

  window.sidebarToggleCompanyMenu = function() {
    const menu = document.getElementById('sb-company-menu');
    if (!menu) return;
    const isOpen = menu.style.display !== 'none';
    if (isOpen) { menu.style.display = 'none'; return; }
    // Position above the user bar (opens UPWARD)
    const bar = document.getElementById('sidebar-user-bar');
    if (bar) {
      const rect = bar.getBoundingClientRect();
      menu.style.bottom = (window.innerHeight - rect.top + 6) + 'px';
      menu.style.top = 'auto';
      menu.style.left = rect.left + 'px';
      menu.style.width = rect.width + 'px';
    }
    menu.style.display = 'block';
  };

  window.sidebarSwitchCompany = async function(id) {
    try {
      const sb = window._supabase || window.supabase;
      if (!sb) return;
      await sb.rpc('switch_company', { p_company_id: id });
      localStorage.setItem('currentCompanyId', id);
      window.location.reload();
    } catch (e) {
      console.error('Switch company error:', e);
    }
  };

  // Ensure showToast is available globally (some pages like dashboard don't define it)
  if (!window.showToast) {
    window.showToast = function(msg, type) {
      let container = document.getElementById('toast-container');
      if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:9999;display:flex;flex-direction:column-reverse;gap:8px;pointer-events:none;';
        document.body.appendChild(container);
      }
      const t = document.createElement('div');
      t.style.cssText = 'padding:14px 20px;border-radius:12px;font-size:13px;font-weight:600;color:#fff;box-shadow:0 8px 24px rgba(0,0,0,0.2);max-width:360px;pointer-events:auto;transition:opacity .3s ease;background:' +
        (type==='error'?'#ef4444':type==='warning'?'#f59e0b':'#10b981');
      t.textContent = msg;
      container.appendChild(t);
      setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 300); }, 3000);
    };
  }

  const SIDEBAR_WAREHOUSE_NAMES = {
    TR:'Ana Depo', EN:'Main Warehouse', DE:'Hauptlager', FR:'Entrepôt Principal',
    ES:'Almacén Principal', PT:'Armazém Principal', IT:'Magazzino Principale',
    NL:'Hoofdmagazijn', RU:'Основной склад', AR:'المستودع الرئيسي',
    ZH:'主仓库', JA:'メイン倉庫', KO:'본 창고', KK:'Негізгі қойма', UZ:'Asosiy ombor',
    AZ:'Əsas anbar', UK:'Основний склад', PL:'Magazyn główny', RO:'Depozit principal',
    HU:'Főraktár', CS:'Hlavní sklad', BG:'Основен склад', HR:'Glavni skladište',
    SR:'Главно складиште', SK:'Hlavný sklad', SL:'Glavno skladišče'
  };

  // Hardcoded fallback country list — used when localizations RPC fails
  // (RLS issue, network down, etc.) so the new-company modal never gets
  // stuck on a "Loading..." placeholder.
  const FALLBACK_COUNTRIES = [
    {country_code:'TR', country_name:'Türkiye'},
    {country_code:'KZ', country_name:'Kazakhstan'},
    {country_code:'KG', country_name:'Kyrgyzstan'},
    {country_code:'UZ', country_name:'Uzbekistan'},
    {country_code:'TM', country_name:'Turkmenistan'},
    {country_code:'AZ', country_name:'Azerbaijan'},
    {country_code:'RU', country_name:'Russia'},
    {country_code:'US', country_name:'United States'},
    {country_code:'GB', country_name:'United Kingdom'},
    {country_code:'DE', country_name:'Germany'},
    {country_code:'FR', country_name:'France'},
    {country_code:'ES', country_name:'Spain'},
    {country_code:'IT', country_name:'Italy'},
    {country_code:'NL', country_name:'Netherlands'},
    {country_code:'PL', country_name:'Poland'},
    {country_code:'PT', country_name:'Portugal'},
    {country_code:'BR', country_name:'Brazil'},
    {country_code:'MX', country_name:'Mexico'},
    {country_code:'CN', country_name:'China'},
    {country_code:'JP', country_name:'Japan'},
    {country_code:'KR', country_name:'South Korea'},
    {country_code:'IN', country_name:'India'},
    {country_code:'AE', country_name:'United Arab Emirates'},
    {country_code:'SA', country_name:'Saudi Arabia'},
    {country_code:'EG', country_name:'Egypt'},
  ];

  function _populateCountrySelect(sel, list) {
    sel.innerHTML = list.map(c => `<option value="${c.country_code}">${c.country_name}</option>`).join('');
    // Make TR default if present
    const tr = list.find(c => c.country_code === 'TR');
    if (tr) sel.value = 'TR';
  }

  window.sidebarOpenNewCompany = async function() {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.add('open');
    const menu = document.getElementById('sb-company-menu');
    if (menu) menu.style.display = 'none';
    // Load countries into dropdown
    const sel = document.getElementById('sb-new-company-country');
    if (sel && (sel.options.length <= 1 || sel.options[0].value === '')) {
      // Show loading state
      sel.innerHTML = '<option value="">Loading…</option>';
      try {
        const sb = window._supabase || window.supabase;
        const { data, error } = await sb.from('localizations').select('country_code, country_name').order('country_name');
        if (error) throw error;
        if (data && data.length) {
          _populateCountrySelect(sel, data);
        } else {
          // Empty result (RLS hiding rows or table empty) → fall back to hardcoded list
          console.warn('[sidebar] localizations returned empty, using fallback country list');
          _populateCountrySelect(sel, FALLBACK_COUNTRIES);
        }
      } catch (e) {
        console.warn('[sidebar] Failed to load countries from DB, using fallback:', e);
        _populateCountrySelect(sel, FALLBACK_COUNTRIES);
      }
    }
  };

  window.sidebarCloseNewCompany = function() {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.remove('open');
  };

  window.sidebarCreateCompany = async function() {
    const toast = window.showToast || function(m) { console.warn(m); };
    const nameInput = document.getElementById('sb-new-company-name');
    const name = nameInput ? nameInput.value.trim() : '';
    if (!name) { toast('Company name is required', 'error'); return; }
    const countryCode = document.getElementById('sb-new-company-country')?.value || 'US';

    // Lock UI
    const btn = document.getElementById('sb-btn-create-company');
    const countrySel = document.getElementById('sb-new-company-country');
    const origText = btn ? btn.textContent : 'Create';
    if (btn) { btn.disabled = true; btn.innerHTML = '<span style="display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .6s linear infinite;vertical-align:middle"></span> Creating...'; }
    if (nameInput) nameInput.disabled = true;
    if (countrySel) countrySel.disabled = true;

    try {
      const sb = window._supabase || window.supabase;
      const { data: { user: currentUser } } = await sb.auth.getUser();
      if (!currentUser) { toast('Not authenticated', 'error'); return; }

      // Use the SECURITY DEFINER RPC — atomic create + owner link.
      // Bypasses the RLS edge cases that bit us when the supabase-js
      // client connection didn't have its role elevated to authenticated.
      const { data: rpcResult, error: rpcError } = await sb.rpc('create_company_for_user', {
        p_name: name,
        p_country_code: countryCode,
        p_base_currency: 'USD',
        p_user_id: currentUser.id,
      });
      if (rpcError) throw rpcError;
      if (!rpcResult || rpcResult.success === false) {
        throw new Error((rpcResult && rpcResult.error) || 'Failed to create company');
      }
      const comp = { id: rpcResult.company_id };

      // Copy tax rates from localization or templates
      const { data: loc } = await sb.from('localizations')
        .select('id, default_language')
        .eq('country_code', countryCode).single();
      let taxLoaded = false;
      if (loc) {
        const { data: taxData } = await sb.from('localization_tax_rates')
          .select('name, rate, description, is_default')
          .eq('localization_id', loc.id);
        if (taxData && taxData.length) {
          await sb.from('tax_rates').insert(
            taxData.map(tr => ({
              company_id: comp.id, name: tr.name, rate: tr.rate,
              description: tr.description, is_default: tr.is_default || false
            }))
          );
          taxLoaded = true;
        }
        // Create default warehouse
        const lang = (loc.default_language || 'EN').toUpperCase();
        const whName = SIDEBAR_WAREHOUSE_NAMES[lang] || SIDEBAR_WAREHOUSE_NAMES['EN'];
        await sb.from('warehouses').insert({ company_id: comp.id, name: whName, is_default: true });
      }
      // Fallback: load from tax_rates_templates if localization had no tax data
      if (!taxLoaded) {
        const { data: tplTax } = await sb.from('tax_rates_templates')
          .select('tax_name, tax_name_local, rate, tax_type, is_default, is_mandatory')
          .eq('country_code', countryCode);
        if (tplTax && tplTax.length) {
          const mandatory = tplTax.filter(t => t.is_mandatory);
          if (mandatory.length) {
            await sb.from('tax_rates').insert(
              mandatory.map(t => ({
                company_id: comp.id, name: t.tax_name_local || t.tax_name,
                rate: t.rate, is_default: t.is_default || false
              }))
            );
          }
        }
      }
      // Insert default modules (all active)
      const ALL_MODULES = ['inventory','sales','purchasing','production','accounting','hr','shipping','projects','maintenance','cash_bank'];
      await sb.from('company_modules').insert(
        ALL_MODULES.map(m => ({ company_id: comp.id, module: m, is_active: true }))
      );

      // Load chart of accounts from templates
      const { data: coaTemplates } = await sb.from('chart_of_accounts_templates')
        .select('account_code, account_name_local, account_name_en, account_type, parent_code, level, is_mandatory')
        .eq('country_code', countryCode)
        .eq('is_mandatory', true);
      if (coaTemplates && coaTemplates.length) {
        const BATCH = 200;
        for (let i = 0; i < coaTemplates.length; i += BATCH) {
          await sb.from('chart_of_accounts').insert(
            coaTemplates.slice(i, i + BATCH).map(t => ({
              company_id: comp.id, code: t.account_code,
              name: t.account_name_en, name_local: t.account_name_local,
              type: t.account_type, parent_code: t.parent_code,
              level: t.level, country_code: countryCode, is_system: true
            }))
          );
        }
      }

      localStorage.setItem('currentCompanyId', comp.id);
      if (btn) btn.innerHTML = '✓ Company created!';
      toast('Company created!', 'success');
      setTimeout(() => { sidebarCloseNewCompany(); window.location.reload(); }, 1500);
    } catch (e) {
      toast('Error: ' + e.message, 'error');
      // Unlock UI on error
      if (btn) { btn.disabled = false; btn.textContent = origText; }
      if (nameInput) nameInput.disabled = false;
      if (countrySel) countrySel.disabled = false;
    }
  };

  window.showConfirm = function(message, title, confirmLabel) {
    return new Promise((resolve) => {
      const overlay = document.getElementById('solvenin-confirm-overlay');
      const msg = document.getElementById('solvenin-confirm-msg');
      const titleEl = document.getElementById('solvenin-confirm-title');
      const okBtn = document.getElementById('solvenin-confirm-ok');
      const cancelBtn = document.getElementById('solvenin-confirm-cancel');
      if (!overlay) { resolve(false); return; }
      titleEl.textContent = title || 'Onay';
      msg.textContent = message;
      okBtn.textContent = confirmLabel || 'Tamam';
      if (cancelBtn) {
        cancelBtn.textContent = 'İptal';
        cancelBtn.style.display = '';
      }
      overlay.classList.add('open');
      window._confirmReject = () => { resolve(false); };
      okBtn.onclick = () => { overlay.classList.remove('open'); resolve(true); };
      if (cancelBtn) cancelBtn.onclick = () => { overlay.classList.remove('open'); resolve(false); };
    });
  };

  window.showAlert = function(message, title) {
    return new Promise((resolve) => {
      const overlay = document.getElementById('solvenin-confirm-overlay');
      const msg = document.getElementById('solvenin-confirm-msg');
      const titleEl = document.getElementById('solvenin-confirm-title');
      const okBtn = document.getElementById('solvenin-confirm-ok');
      const cancelBtn = document.getElementById('solvenin-confirm-cancel');
      if (!overlay) { resolve(); return; }
      titleEl.textContent = title || 'Bilgi';
      msg.textContent = message;
      okBtn.textContent = 'Tamam';
      if (cancelBtn) cancelBtn.style.display = 'none';
      overlay.classList.add('open');
      okBtn.onclick = () => { overlay.classList.remove('open'); if (cancelBtn) cancelBtn.style.display = ''; resolve(); };
    });
  };

  window.showPrompt = function(message, defaultValue, title) {
    return new Promise((resolve) => {
      const overlay = document.getElementById('solvenin-confirm-overlay');
      const msg = document.getElementById('solvenin-confirm-msg');
      const titleEl = document.getElementById('solvenin-confirm-title');
      const okBtn = document.getElementById('solvenin-confirm-ok');
      const cancelBtn = document.getElementById('solvenin-confirm-cancel');
      if (!overlay) { resolve(null); return; }
      titleEl.textContent = title || 'Giriş';
      msg.innerHTML = message + '<br><input id="solvenin-prompt-input" type="text" value="' + (defaultValue || '').replace(/"/g, '&quot;') + '" style="width:100%;margin-top:10px;padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:14px;box-sizing:border-box;">';
      okBtn.textContent = 'Tamam';
      if (cancelBtn) {
        cancelBtn.textContent = (window.t && window.t('btn_cancel')) || 'İptal';
        cancelBtn.style.display = '';
      }
      overlay.classList.add('open');
      setTimeout(() => { const inp = document.getElementById('solvenin-prompt-input'); if (inp) { inp.focus(); inp.select(); } }, 100);
      okBtn.onclick = () => { const v = document.getElementById('solvenin-prompt-input')?.value; overlay.classList.remove('open'); resolve(v); };
      if (cancelBtn) cancelBtn.onclick = () => { overlay.classList.remove('open'); resolve(null); };
    });
  };

  /* ── AI CHAT ─────────────────────────────────────────────── */
  const AI_RATE_KEY      = 'ai_daily_count';
  const AI_RATE_DATE_KEY = 'ai_daily_date';
  const AI_MAX_DAILY     = 20;
  const AI_SYSTEM = `Sen Solvenin ERP'nin AI asistanısın.
Kullanıcıyla doğal, samimi ve kısa konuş. Sanki deneyimli bir iş arkadaşısın.

KONUŞMA KURALLARI:
- Emoji KULLANMA — hiç
- Markdown tablo KULLANMA — sayıları düz yaz
- Kısa ve öz cevap ver
- Robotik liste yapma, cümleyle anlat
- "Toplam cironuz şu kadar, tahsilat oranı çok iyi" gibi konuş
- Para birimini her zaman sonuna yaz (26.821.600 tenge gibi)
- Kullanıcının diline göre konuş (TR/RU/KZ)

ÖRNEK İYİ CEVAP:
"Bu ay 26 sipariş, toplam 26.8 milyon tenge ciro yaptınız. Tahsilat çok iyi — sadece 41 bin tenge ödeme bekliyor."

ÖRNEK KÖTÜ CEVAP:
"## 📊 Bu Ayın Satış Tutarları
| Metrik | Değer |
|--------|-------|
| 💰 Toplam Ciro | 26.821.600 ₸ |"

Araç kullanırken sessiz ol — sonucu direkt anlat.

Kullanıcının şirket verilerine doğrudan erişebilirsin (sales, purchases, products, contacts, cash/bank, payments).
Kullanıcı veri sorduğunda araçları kullanarak gerçek sayıları getir ve göster. Asla "şu sayfaya gidin" deme — verileri sen çek ve özetle.
Para birimi formatı: tenge, lira, dolar veya euro. Sayıları binlik ayraçla göster.
Solvenin modülleri: Envanter, Satış, Satın Alma, Üretim, Kasa & Banka, Muhasebe, İK & Bordro, Sevkiyat, Projeler, Bakım, CRM, POS, Stok Sayımı.
Çözemediğin yazılım sorunlarında support@solvenin.com adresini öner.`;

  let _aiHistory  = [];
  let _aiStreaming = false;

  function aiRatePassed() {
    const today = new Date().toDateString();
    if (localStorage.getItem(AI_RATE_DATE_KEY) !== today) {
      localStorage.setItem(AI_RATE_DATE_KEY, today);
      localStorage.setItem(AI_RATE_KEY, '0');
    }
    return parseInt(localStorage.getItem(AI_RATE_KEY) || '0') < AI_MAX_DAILY;
  }

  function aiRemaining() {
    const today = new Date().toDateString();
    if (localStorage.getItem(AI_RATE_DATE_KEY) !== today) return AI_MAX_DAILY;
    return AI_MAX_DAILY - parseInt(localStorage.getItem(AI_RATE_KEY) || '0');
  }

  function aiIncrRate() {
    localStorage.setItem(AI_RATE_KEY, String(parseInt(localStorage.getItem(AI_RATE_KEY) || '0') + 1));
  }

  function aiAppend(role, text, id) {
    const msgs = document.getElementById('ai-chat-messages');
    if (!msgs) return null;
    const div = document.createElement('div');
    div.className = `ai-msg ai-msg-${role}`;
    if (id)   div.id          = id;
    if (text) div.textContent = text;
    if (role === 'assistant') {
      const wrap = document.createElement('div');
      wrap.className = 'ai-msg-wrap ai-wrap-assistant';
      wrap.appendChild(div);
      const speakBtn = document.createElement('button');
      speakBtn.className = 'ai-speak-btn';
      speakBtn.textContent = '🔊';
      speakBtn.title = 'Sesli oku';
      speakBtn.onclick = () => aiSpeakText(div.textContent, speakBtn);
      wrap.appendChild(speakBtn);
      msgs.appendChild(wrap);
    } else {
      msgs.appendChild(div);
    }
    msgs.scrollTop = msgs.scrollHeight;
    return div;
  }

  function aiUpdateRemaining() {
    const el = document.getElementById('ai-remaining');
    if (el) el.textContent = `${aiRemaining()}/${AI_MAX_DAILY} mesaj kaldı`;
  }

  async function injectAIFloatingButton() {
    // Remove legacy locations
    document.getElementById('ai-floating-btn')?.remove();
    document.getElementById('sb-ai-btn')?.remove();

    // Inject into topbar — place between search bar and topbar-actions (bell/help)
    let btn = document.getElementById('topbar-ai-btn');
    if (!btn) {
      const actions = document.querySelector('.topbar .topbar-actions');
      const topbar = document.querySelector('.topbar');
      if (!topbar) return;
      btn = document.createElement('button');
      btn.id = 'topbar-ai-btn';
      btn.type = 'button';
      btn.title = 'AI Asistan';
      btn.innerHTML = '<span class="ai-icon">✨</span><span class="ai-label">AI Asistan</span>';
      btn.onclick = () => window.sidebarOpenAI && window.sidebarOpenAI();
      if (actions && actions.parentNode === topbar) {
        topbar.insertBefore(btn, actions);
      } else {
        topbar.appendChild(btn);
      }
    }

    // Visibility gate — ai_assistant_enabled for current user in current company
    try {
      const sb = window._supabase || window.supabase;
      if (!sb || !sb.auth) return;
      const { data: { user } } = await sb.auth.getUser();
      if (!user) return;
      const companyId = localStorage.getItem('currentCompanyId');
      if (!companyId) return;
      const { data: cu } = await sb.from('company_users')
        .select('ai_assistant_enabled')
        .eq('company_id', companyId).eq('user_id', user.id).single();
      if (cu?.ai_assistant_enabled) btn.classList.add('visible');
    } catch (e) { /* silent — button stays hidden */ }
  }

  function injectAIPanel() {
    if (document.getElementById('ai-chat-panel')) return;
    const panel = document.createElement('div');
    panel.id = 'ai-chat-panel';
    panel.innerHTML = `
      <div class="ai-chat-header">
        <div class="ai-chat-header-icon">🤖</div>
        <div class="ai-chat-header-title">
          <strong>Solvenin AI Asistan</strong>
          <span>Her konuda yardımcı olurum</span>
        </div>
        <label class="ai-autospeak-toggle" title="Otomatik Sesli Yanıt">
          <input type="checkbox" id="ai-autospeak-cb" onchange="aiSetAutospeak(this.checked)"
            ${localStorage.getItem('solvenin_ai_autospeak')==='true'?'checked':''}>
          🔊
        </label>
        <button class="ai-chat-close" onclick="sidebarCloseAI()">✕</button>
      </div>
      <div class="ai-chat-messages" id="ai-chat-messages"></div>
      <div id="ai-support-container">
        <button class="ai-support-btn" onclick="aiOpenSupport()">📩 Destek Talebi Oluştur</button>
      </div>
      <div class="ai-chat-footer">
        <div class="ai-chat-footer-meta" id="ai-remaining">${aiRemaining()}/${AI_MAX_DAILY} mesaj kaldı</div>
        <div class="ai-chat-input-row">
          <textarea id="ai-chat-input" placeholder="Mesajınızı yazın..." rows="1"
            onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();aiSendMessage();}"
            oninput="this.style.height='auto';this.style.height=Math.min(this.scrollHeight,120)+'px'"></textarea>
          <button id="ai-mic-btn" class="ai-mic-btn" title="Sesli komut" onclick="aiToggleVoice()">🎤</button>
          <button id="ai-send-btn" onclick="aiSendMessage()">Gönder</button>
        </div>
      </div>`;
    document.body.appendChild(panel);
  }

  window.sidebarOpenAI = function() {
    let panel = document.getElementById('ai-chat-panel');
    if (!panel) { injectAIPanel(); panel = document.getElementById('ai-chat-panel'); }
    if (!panel) return;
    panel.classList.add('open');
    const msgs = document.getElementById('ai-chat-messages');
    if (msgs && !msgs.children.length) {
      aiAppend('assistant', 'Merhaba! Ben Solvenin AI Asistanıyım. Size nasıl yardımcı olabilirim?');
    }
    const inp = document.getElementById('ai-chat-input');
    if (inp) inp.focus();
  };

  window.sidebarCloseAI = function() {
    window.speechSynthesis?.cancel();
    _aiActiveSpeakBtn = null;
    const panel = document.getElementById('ai-chat-panel');
    if (panel) panel.classList.remove('open');
  };

  window.aiOpenSupport = function() {
    const sub  = encodeURIComponent('Destek Talebi – ' + document.title);
    const body = encodeURIComponent('Merhaba,\n\nAI Asistan çözüm bulamadı. Yardıma ihtiyacım var.\n\nSayfa: ' + window.location.href);
    window.open('mailto:support@solvenin.com?subject=' + sub + '&body=' + body);
  };

  window.aiSendMessage = async function() {
    if (_aiStreaming) return;
    window.speechSynthesis?.cancel();
    _aiActiveSpeakBtn = null;
    const input = document.getElementById('ai-chat-input');
    if (!input) return;
    const text = input.value.trim();
    if (!text) return;

    if (!aiRatePassed()) {
      aiAppend('system', `⚠️ Günlük mesaj limitinize (${AI_MAX_DAILY}) ulaştınız. Yarın tekrar deneyiniz.`);
      return;
    }

    input.value = '';
    input.style.height = 'auto';
    aiAppend('user', text);
    _aiHistory.push({ role: 'user', content: text });
    aiIncrRate();
    aiUpdateRemaining();

    const sendBtn = document.getElementById('ai-send-btn');
    _aiStreaming    = true;
    input.disabled  = true;
    if (sendBtn) { sendBtn.disabled = true; sendBtn.textContent = '...'; }

    const msgId  = 'ai-msg-' + Date.now();
    const bubble = aiAppend('assistant', '', msgId);

    const pageCtx = `Kullanıcı şu an "${document.title}" sayfasında (${window.location.pathname}).`;

    try {
      // Proxy via claude-proxy edge function — resolves CORS + keeps key server-side
      const sbc = window._supabase || window.supabase;
      if (!sbc) throw new Error('Supabase client not ready');
      const el = document.getElementById(msgId);
      if (el) el.textContent = '…';
      const companyId = localStorage.getItem('currentCompanyId');
      const { data, error } = await sbc.functions.invoke('claude-proxy', {
        body: {
          model: 'claude-sonnet-4-20250514',
          max_tokens: 2048,
          system: AI_SYSTEM + '\n\n' + pageCtx,
          messages: _aiHistory,
          companyId,
          useTools: true
        }
      });
      if (error) throw new Error(error.message || 'edge fn error');
      if (data?.error) throw new Error(data.error?.message || data.error);
      const fullText = (data?.content || []).map(b => b.text || '').join('');
      if (el) {
        el.textContent = fullText;
        const msgs = document.getElementById('ai-chat-messages');
        if (msgs) msgs.scrollTop = msgs.scrollHeight;
      }
      _aiHistory.push({ role: 'assistant', content: fullText });

      if (localStorage.getItem('solvenin_ai_autospeak') === 'true' && fullText) {
        const wrap = el?.closest('.ai-msg-wrap');
        const btn = wrap?.querySelector('.ai-speak-btn');
        aiSpeakText(fullText, btn);
      }

      // Show support button if AI can't resolve
      if (/support@solvenin\.com|çözemiyorum|bilemiyorum|emin değilim/i.test(fullText)) {
        const sc = document.getElementById('ai-support-container');
        if (sc) sc.style.display = 'flex';
      }

    } catch (e) {
      const el = document.getElementById(msgId);
      if (el) el.textContent = '⚠️ Hata: ' + e.message;
    }

    _aiStreaming     = false;
    input.disabled   = false;
    if (sendBtn) { sendBtn.disabled = false; sendBtn.textContent = 'Gönder'; }
    input.focus();
    aiUpdateRemaining();
  };

  /* ── TEXT-TO-SPEECH ───────────────────────────────────────── */
  let _aiActiveSpeakBtn = null;

  const _aiTTSLangMap = { tr:'tr-TR', en:'en-US', ru:'ru-RU', kz:'kk-KZ', de:'de-DE', fr:'fr-FR', es:'es-ES', ar:'ar-SA', zh:'zh-CN', ja:'ja-JP', pt:'pt-PT' };

  function aiCleanTextForTTS(text) {
    return text
      .replace(/#{1,6}\s/g, '')
      .replace(/\*\*/g, '').replace(/\*/g, '')
      .replace(/\|/g, ' ').replace(/[-]{3,}/g, '')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/`/g, '')
      .replace(/[\u{1F000}-\u{1FFFF}]/gu, '')
      .replace(/[\u{2600}-\u{27FF}]/gu, '')
      .replace(/[\u{FE00}-\u{FEFF}]/gu, '')
      .replace(/[\u{1F900}-\u{1F9FF}]/gu, '')
      .replace(/[\u2702-\u27B0]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function aiSpeakText(text, btn) {
    if (!window.speechSynthesis) return;
    if (_aiActiveSpeakBtn) {
      window.speechSynthesis.cancel();
      _aiActiveSpeakBtn.classList.remove('speaking');
      if (_aiActiveSpeakBtn === btn) { _aiActiveSpeakBtn = null; return; }
    }

    let clean = aiCleanTextForTTS(text);
    if (clean.length > 500) {
      const sentences = clean.match(/[^.!?…]+[.!?…]+/g) || [clean];
      clean = sentences.slice(0, 3).join(' ').trim() + ' … devamı için metni okuyun.';
    }

    const utt = new SpeechSynthesisUtterance(clean);
    const lang = localStorage.getItem('solvenin_lang') || 'tr';
    utt.lang   = _aiTTSLangMap[lang] || 'tr-TR';
    utt.rate   = 1.0;
    utt.pitch  = 1.0;

    const voices = window.speechSynthesis.getVoices();
    const pref = voices.find(v => v.lang.startsWith(utt.lang.split('-')[0]));
    if (pref) utt.voice = pref;

    _aiActiveSpeakBtn = btn || null;

    utt.onstart = () => { if (_aiActiveSpeakBtn) _aiActiveSpeakBtn.classList.add('speaking'); };
    utt.onend   = () => { if (_aiActiveSpeakBtn) _aiActiveSpeakBtn.classList.remove('speaking'); _aiActiveSpeakBtn = null; };
    utt.onerror = () => { if (_aiActiveSpeakBtn) _aiActiveSpeakBtn.classList.remove('speaking'); _aiActiveSpeakBtn = null; };

    window.speechSynthesis.speak(utt);
  }
  window.aiSpeakText = aiSpeakText;

  window.aiSetAutospeak = function(on) {
    localStorage.setItem('solvenin_ai_autospeak', on ? 'true' : 'false');
  };

  /* ── VOICE INPUT ──────────────────────────────────────────── */
  const _SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
  let _aiRecognition = null;
  let _aiRecording   = false;

  function aiInitVoice() {
    const micBtn = document.getElementById('ai-mic-btn');
    if (!micBtn) return;
    if (!_SpeechRec) { micBtn.style.display = 'none'; return; }
    if (_aiRecognition) return;

    const rec = new _SpeechRec();
    rec.continuous      = false;
    rec.interimResults  = true;
    rec.maxAlternatives = 1;

    const langMap = { tr:'tr-TR', en:'en-US', ru:'ru-RU', kz:'kk-KZ', de:'de-DE', fr:'fr-FR', es:'es-ES', ar:'ar-SA', zh:'zh-CN', ja:'ja-JP', pt:'pt-PT' };
    const lang = localStorage.getItem('solvenin_lang') || 'tr';
    rec.lang = langMap[lang] || 'tr-TR';

    rec.onstart = () => {
      _aiRecording = true;
      if (micBtn) { micBtn.textContent = '⏹️'; micBtn.classList.add('recording'); micBtn.title = 'Dinleniyor…'; }
      const inp = document.getElementById('ai-chat-input');
      if (inp) inp.placeholder = 'Dinleniyor…';
    };

    rec.onresult = (ev) => {
      let transcript = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) transcript += ev.results[i][0].transcript;
      const inp = document.getElementById('ai-chat-input');
      if (inp) inp.value = transcript;
      if (ev.results[ev.results.length - 1].isFinal) {
        setTimeout(() => { if (inp && inp.value.trim()) aiSendMessage(); }, 500);
      }
    };

    rec.onend = () => {
      _aiRecording = false;
      if (micBtn) { micBtn.textContent = '🎤'; micBtn.classList.remove('recording'); micBtn.title = 'Sesli komut'; }
      const inp = document.getElementById('ai-chat-input');
      if (inp) inp.placeholder = 'Mesajınızı yazın...';
    };

    rec.onerror = (ev) => {
      _aiRecording = false;
      if (micBtn) { micBtn.textContent = '🎤'; micBtn.classList.remove('recording'); }
      if (ev.error === 'not-allowed') showToast('Mikrofon erişimine izin verin', 'error');
      else if (ev.error === 'no-speech') showToast('Ses algılanamadı, tekrar deneyin', 'warning');
    };

    _aiRecognition = rec;
  }

  window.aiToggleVoice = function() {
    aiInitVoice();
    if (!_aiRecognition) return;
    if (_aiRecording) { _aiRecognition.stop(); return; }
    window.speechSynthesis?.cancel();
    _aiActiveSpeakBtn = null;
    try { _aiRecognition.start(); } catch(e) { /* already started */ }
  };

  /* ── LANGUAGE CHANGE — re-render preserving open state ───── */
  document.addEventListener('langChanged', function() {
    const sb = document.getElementById('sidebar');
    if (sb) {
      sb.innerHTML = buildHTML();
      loadSidebarData();
    }
  });

  /* ── INIT ────────────────────────────────────────────────── */
  function waitForSupabase(cb) {
    const wait = setInterval(() => {
      if (window._supabase || window.supabase) {
        clearInterval(wait);
        cb();
      }
    }, 100);
    setTimeout(() => clearInterval(wait), 5000);
  }

  function tryMount() {
    if (document.body) {
      mount();
      window._sidebarMounted = true;
      document.dispatchEvent(new Event('sidebarMounted'));
      waitForSupabase(loadSidebarData);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', tryMount);
  } else {
    tryMount();
  }

})();
