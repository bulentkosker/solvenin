/* ============================================================
   sidebar.js — Solvenin ERP Shared Sidebar
   Tüm sayfalarda tek kaynak. Değiştirmek için sadece bu dosya.
   ============================================================ */

(function () {

  /* ── CSS ─────────────────────────────────────────────────── */
  const CSS = `
    :root {
      --sidebar-w: 220px;
      --sb-bg:       #0a2e20;
      --sb-accent:   #f0a500;
      --sb-accent2:  #d4900a;
      --font-display: 'Outfit', sans-serif;
    }
    .sidebar {
      width: var(--sidebar-w); background: var(--sb-bg);
      min-height: 100vh; position: fixed; top: 0; left: 0;
      display: flex; flex-direction: column; z-index: 50;
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
    .sidebar-section { padding: 8px 8px 4px; }
    .sidebar-section-label {
      font-size: 9px; font-weight: 700; letter-spacing: 2px;
      text-transform: uppercase; color: rgba(255,255,255,0.4);
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
    .nav-item:hover { background: rgba(255,255,255,0.08); color: #fff; }
    .nav-item.active {
      background: rgba(13,79,60,0.45); color: #fff; font-weight: 600;
      border-left-color: var(--sb-accent);
    }
    .nav-item.active .nav-icon { color: var(--sb-accent); }
    .nav-icon { font-size: 13px; width: 16px; text-align: center; flex-shrink: 0; }
    .nav-badge {
      margin-left: auto; background: rgba(240,165,0,0.25);
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
    .nav-parent:hover { background: rgba(255,255,255,0.08); color: #fff; }
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
    .nav-child:hover { background: rgba(255,255,255,0.08); color: rgba(255,255,255,0.9); }
    .nav-child.active {
      background: rgba(13,79,60,0.4); color: var(--sb-accent); font-weight: 600;
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
    .sidebar-footer { padding: 10px; border-top: 1px solid rgba(255,255,255,0.08); }
    .company-switcher {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; margin: 0 0 4px;
      border-radius: 8px; cursor: pointer;
      background: rgba(255,255,255,0.07);
      border: 1px solid rgba(255,255,255,0.1);
      transition: background .15s;
    }
    .company-switcher:hover { background: rgba(240,165,0,0.15); }
    .company-icon { font-size: 15px; flex-shrink: 0; }
    .company-info { flex: 1; min-width: 0; }
    .company-name {
      font-size: 11px; font-weight: 700; color: #fff;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .company-plan { font-size: 10px; color: rgba(255,255,255,0.4); text-transform: uppercase; letter-spacing: .5px; }
    .company-chevron { color: rgba(255,255,255,0.4); font-size: 13px; flex-shrink: 0; }
    .company-menu {
      margin: 0 0 6px; border-radius: 10px;
      background: #fff;
      border: 1px solid #e8e4dc;
      box-shadow: 0 8px 24px rgba(0,0,0,0.15);
      overflow: hidden;
    }
    .company-menu-item {
      display: flex; align-items: center; gap: 10px;
      padding: 8px 12px; cursor: pointer; transition: background .15s;
    }
    .company-menu-item:hover { background: #f8f7f4; }
    .company-menu-item.active { background: rgba(13,79,60,0.07); }
    .company-menu-item .c-dot {
      width: 7px; height: 7px; border-radius: 50%;
      background: #d1cdc4; flex-shrink: 0;
    }
    .company-menu-item.active .c-dot { background: #0d4f3c; }
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
    .company-menu-footer button:hover { background: rgba(13,79,60,0.07); color: #0d4f3c; border-color: #0d4f3c; }

    /* ── User card ── */
    .user-card {
      display: flex; align-items: center; gap: 8px;
      padding: 7px 8px; border-radius: 8px; cursor: pointer; transition: all .15s;
    }
    .user-card:hover { background: rgba(255,255,255,0.08); }
    .user-avatar {
      width: 30px; height: 30px; border-radius: 8px;
      background: rgba(240,165,0,0.3);
      display: flex; align-items: center; justify-content: center;
      font-weight: 700; color: #fff; font-size: 12px; flex-shrink: 0;
    }
    .user-name { font-size: 11px; font-weight: 600; color: #fff; }
    .user-plan { font-size: 10px; color: rgba(255,255,255,0.4); margin-top: 1px; }
    .user-menu-btn { margin-left: auto; color: rgba(255,255,255,0.25); font-size: 16px; }

    /* ── AI Button ── */
    .ai-btn {
      width: 100%; padding: 9px 12px; border-radius: 8px;
      border: 1.5px solid rgba(240,165,0,0.3);
      background: rgba(240,165,0,0.08); color: var(--sb-accent);
      font-size: 12px; font-weight: 600; cursor: pointer;
      transition: all .15s; text-align: left; margin-top: 6px;
      display: flex; align-items: center; gap: 8px;
    }
    .ai-btn:hover { background: rgba(240,165,0,0.2); border-color: var(--sb-accent); }

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
      background: linear-gradient(135deg, #0d4f3c 0%, #0a2e20 100%);
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
      background: #0d4f3c; color: #fff;
      align-self: flex-end; border-bottom-right-radius: 4px;
    }
    .ai-msg-assistant {
      background: #fff; color: #1a1a2e;
      align-self: flex-start; border-bottom-left-radius: 4px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.08);
    }
    .ai-msg-system {
      background: rgba(240,165,0,0.1); color: #8a6200;
      border: 1px solid rgba(240,165,0,0.3); border-radius: 8px;
      font-size: 11.5px; align-self: center; text-align: center; max-width: 90%;
    }
    #ai-support-container {
      display: none; padding: 8px 14px; background: #fff8ed;
      border-top: 1px solid #fce8b2; justify-content: center; flex-shrink: 0;
    }
    .ai-support-btn {
      padding: 7px 16px; border-radius: 8px;
      background: #f0a500; color: #fff; border: none;
      font-size: 12px; font-weight: 600; cursor: pointer; transition: background .15s;
    }
    .ai-support-btn:hover { background: #d4900a; }
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
    #ai-chat-input:focus { border-color: #0d4f3c; box-shadow: 0 0 0 3px rgba(13,79,60,0.08); }
    #ai-send-btn {
      padding: 0 14px; border-radius: 10px; height: 38px;
      background: #0d4f3c; color: #fff; border: none;
      font-size: 13px; font-weight: 600; cursor: pointer;
      transition: all .15s; white-space: nowrap; flex-shrink: 0;
    }
    #ai-send-btn:hover:not(:disabled) { background: #0a2e20; }
    #ai-send-btn:disabled { opacity: 0.5; cursor: not-allowed; }

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
    .new-company-box input:focus { border-color: #0d4f3c; box-shadow: 0 0 0 3px rgba(13,79,60,0.1); }
    .new-company-box .btn-row { display: flex; gap: 10px; justify-content: flex-end; }
    .new-company-box .btn-cancel {
      padding: 8px 18px; border-radius: 8px; border: 1.5px solid #e8e4dc;
      background: none; color: #6b6560; font-size: 13px; cursor: pointer;
    }
    .new-company-box .btn-create {
      padding: 8px 18px; border-radius: 8px; border: none;
      background: #0d4f3c; color: #fff; font-size: 13px;
      font-weight: 600; cursor: pointer; transition: background .15s;
    }
    .new-company-box .btn-create:hover { background: #0a2e20; }
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
            { key: 'nav_warehouses',      href: 'settings.html#warehouses' },
          ]
        },
        {
          icon: '💰', key: 'nav_sales', href: 'sales.html',
          children: [
            { key: 'nav_sales_orders', href: 'sales.html' },
            { key: 'nav_customers',    href: 'sales.html#customers' },
            { key: 'nav_payments',     href: 'sales.html#payments' },
          ]
        },
        {
          icon: '🛒', key: 'nav_purchasing', href: 'purchasing.html',
          children: [
            { key: 'nav_purchase_orders', href: 'purchasing.html' },
            { key: 'nav_suppliers',       href: 'purchasing.html#suppliers' },
          ]
        },
        { icon: '🏭', key: 'nav_production', href: 'production.html' },
      ]
    },
    {
      labelKey: 'nav_group_finance',
      items: [
        {
          icon: '💳', key: 'nav_finance', href: null,
          children: [
            { key: 'nav_cashbank',   href: 'cashbank.html' },
            { key: 'nav_accounting', href: 'accounting.html' },
          ]
        },
        { icon: '📊', key: 'nav_reports', href: '#' },
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
        { icon: '⚙️', key: 'nav_settings',     href: 'settings.html' },
        { icon: '💎', key: 'nav_subscription', href: 'subscription.html' },
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

  /* ── BUILD HTML ──────────────────────────────────────────── */
  function buildHTML() {
    const page = currentPage();
    const _t = window.t || (k => k);
    let sectionsHTML = '';

    NAV.forEach(section => {
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
            return `<a class="nav-child${active ? ' active' : ''}" href="${child.href || '#'}">
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
          // ── Regular nav item ──
          const active = item.href && item.href !== '#' && page === item.href;
          const label = _t(item.key) || item.key;
          return `<a class="nav-item${active ? ' active' : ''}" href="${item.href || '#'}">
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
        <div class="company-switcher" id="company-switcher" onclick="sidebarToggleCompanyMenu()">
          <div class="company-icon">🏢</div>
          <div class="company-info">
            <div class="company-name" id="sb-company-name">Loading...</div>
            <div class="company-plan" id="sb-company-plan">—</div>
          </div>
          <div class="company-chevron">⌄</div>
        </div>
        <div class="company-menu" id="sb-company-menu" style="display:none">
          <div class="company-menu-list" id="sb-company-menu-list"></div>
          <div class="company-menu-footer" id="sb-company-menu-footer"></div>
        </div>
        <div class="user-card" id="sb-user-card">
          <div class="user-avatar" id="sb-user-avatar">?</div>
          <div class="user-info">
            <div class="user-name" id="sb-user-name">Loading...</div>
            <div class="user-plan" id="sb-user-plan">Free Plan</div>
          </div>
        </div>
        <button class="ai-btn" onclick="sidebarOpenAI()">
          <span>🤖</span><span>AI Asistan</span>
        </button>
      </div>

      <!-- New Company Modal -->
      <div class="new-company-modal" id="sb-new-company-modal">
        <div class="new-company-box">
          <h3>New Company</h3>
          <p>Create a new company to manage separately.</p>
          <input type="text" id="sb-new-company-name" placeholder="Company name..." />
          <div class="btn-row">
            <button class="btn-cancel" onclick="sidebarCloseNewCompany()">Cancel</button>
            <button class="btn-create" onclick="sidebarCreateCompany()">Create</button>
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

    // Inject AI chat panel if not exists
    injectAIPanel();

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
  async function loadSidebarData() {
    try {
      const sb = window._supabase || window.supabase;
      if (!sb) return;

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

      const { data: company } = await sb
        .from('companies')
        .select('name, plan, base_currency')
        .eq('id', companyId)
        .single();

      if (company) {
        const cnEl = document.getElementById('sb-company-name');
        const cpEl = document.getElementById('sb-company-plan');
        if (cnEl) cnEl.textContent = company.name;
        if (cpEl) cpEl.textContent = company.plan || 'Free';
        if (company.base_currency) {
          localStorage.setItem('baseCurrency', company.base_currency);
          document.dispatchEvent(new CustomEvent('currencyLoaded', { detail: company.base_currency }));
        }
      }

      const { data: companies } = await sb.rpc('get_my_companies');
      if (companies) renderCompanyMenu(companies, companyId);

    } catch (e) {
      console.error('Sidebar data error:', e);
    }
  }

  function renderCompanyMenu(companies, currentId) {
    const list = document.getElementById('sb-company-menu-list');
    const footer = document.getElementById('sb-company-menu-footer');
    if (!list) return;

    list.innerHTML = companies.map(c => `
      <div class="company-menu-item ${c.id === currentId ? 'active' : ''} ${c.status === 'suspended' ? 'suspended' : ''}"
           onclick="sidebarSwitchCompany('${c.id}')">
        <div class="c-dot"></div>
        <div class="c-label">${c.name}</div>
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

  window.sidebarToggleCompanyMenu = function() {
    const menu = document.getElementById('sb-company-menu');
    if (menu) menu.style.display = menu.style.display === 'none' ? 'block' : 'none';
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

  window.sidebarOpenNewCompany = function() {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.add('open');
    const menu = document.getElementById('sb-company-menu');
    if (menu) menu.style.display = 'none';
  };

  window.sidebarCloseNewCompany = function() {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.remove('open');
  };

  window.sidebarCreateCompany = async function() {
    const nameInput = document.getElementById('sb-new-company-name');
    const name = nameInput ? nameInput.value.trim() : '';
    if (!name) return;
    try {
      const sb = window._supabase || window.supabase;
      const { data: { user } } = await sb.auth.getUser();
      const { data, error } = await sb.from('companies').insert({
        name,
        owner_id: user.id,
        plan: 'free'
      }).select().single();
      if (error) throw error;
      await sb.from('company_users').insert({
        company_id: data.id,
        user_id: user.id,
        role: 'owner',
        status: 'active'
      });
      localStorage.setItem('currentCompanyId', data.id);
      window.location.reload();
    } catch (e) {
      alert('Error: ' + e.message);
    }
  };

  window.showConfirm = function(message, title, confirmLabel) {
    return new Promise((resolve) => {
      const overlay = document.getElementById('solvenin-confirm-overlay');
      const msg = document.getElementById('solvenin-confirm-msg');
      const titleEl = document.getElementById('solvenin-confirm-title');
      const okBtn = document.getElementById('solvenin-confirm-ok');
      const cancelBtn = document.getElementById('solvenin-confirm-cancel');
      if (!overlay) { resolve(window.confirm(message)); return; }
      titleEl.textContent = title || 'Confirm';
      msg.textContent = message;
      okBtn.textContent = confirmLabel || 'Delete';
      if (cancelBtn) cancelBtn.textContent = (window.t && window.t('btn_cancel')) || 'Cancel';
      overlay.classList.add('open');
      window._confirmReject = () => { resolve(false); };
      okBtn.onclick = () => {
        overlay.classList.remove('open');
        resolve(true);
      };
    });
  };

  /* ── AI CHAT ─────────────────────────────────────────────── */
  const AI_RATE_KEY      = 'ai_daily_count';
  const AI_RATE_DATE_KEY = 'ai_daily_date';
  const AI_MAX_DAILY     = 20;
  const AI_SYSTEM = `Sen Solvenin ERP yazılımının AI asistanısın. Solvenin şu modüllere sahip: Envanter, Satış, Satın Alma, Üretim, Kasa & Banka, Muhasebe, İK & Bordro, Sevkiyat, Projeler, Bakım. Kullanıcıların sorularını Türkçe yanıtla. Yazılımla ilgili sorunları çöz, nasıl kullanılacağını anlat. Çözemediğin durumlarda support@solvenin.com adresine başvurmalarını öner.`;

  let _aiApiKey   = null;
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

  async function aiGetApiKey() {
    if (_aiApiKey) return _aiApiKey;
    try {
      const sb = window._supabase || window.supabase;
      if (!sb) return null;
      const { data } = await sb.from('app_settings').select('value').eq('key', 'anthropic_api_key').single();
      _aiApiKey = data?.value || null;
    } catch (e) { /* not configured */ }
    return _aiApiKey;
  }

  function aiAppend(role, text, id) {
    const msgs = document.getElementById('ai-chat-messages');
    if (!msgs) return null;
    const div = document.createElement('div');
    div.className = `ai-msg ai-msg-${role}`;
    if (id)   div.id          = id;
    if (text) div.textContent = text;
    msgs.appendChild(div);
    msgs.scrollTop = msgs.scrollHeight;
    return div;
  }

  function aiUpdateRemaining() {
    const el = document.getElementById('ai-remaining');
    if (el) el.textContent = `${aiRemaining()}/${AI_MAX_DAILY} mesaj kaldı`;
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
    const input = document.getElementById('ai-chat-input');
    if (!input) return;
    const text = input.value.trim();
    if (!text) return;

    if (!aiRatePassed()) {
      aiAppend('system', `⚠️ Günlük mesaj limitinize (${AI_MAX_DAILY}) ulaştınız. Yarın tekrar deneyiniz.`);
      return;
    }

    const apiKey = await aiGetApiKey();
    if (!apiKey) {
      aiAppend('system', '⚠️ Anthropic API anahtarı bulunamadı. Ayarlar > Uygulama Ayarları bölümünden ekleyin.');
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
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-allow-browser': 'true'
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: 1024,
          stream: true,
          system: AI_SYSTEM + '\n\n' + pageCtx,
          messages: _aiHistory
        })
      });

      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error(err.error?.message || 'HTTP ' + resp.status);
      }

      const reader  = resp.body.getReader();
      const decoder = new TextDecoder();
      let fullText  = '';
      const msgs    = document.getElementById('ai-chat-messages');

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = decoder.decode(value, { stream: true });
        for (const line of chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          const raw = line.slice(6).trim();
          if (!raw || raw === '[DONE]') continue;
          try {
            const ev = JSON.parse(raw);
            if (ev.type === 'content_block_delta' && ev.delta?.type === 'text_delta') {
              fullText += ev.delta.text;
              const el = document.getElementById(msgId);
              if (el) { el.textContent = fullText; if (msgs) msgs.scrollTop = msgs.scrollHeight; }
            }
          } catch (_) {}
        }
      }

      _aiHistory.push({ role: 'assistant', content: fullText });

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
