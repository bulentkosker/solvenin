/* ============================================================
   sidebar.js — Solvenin ERP Shared Sidebar
   Tüm sayfalarda tek kaynak. Değiştirmek için sadece bu dosya.
   ============================================================ */

(function () {

  /* ── CSS ─────────────────────────────────────────────────── */
  const CSS = `
    :root {
      --sidebar-w: 220px;
      --navy: #0a1628;
      --accent: #60a5fa;
      --accent2: #93c5fd;
      --font-display: 'Outfit', sans-serif;
    }
    .sidebar {
      width: var(--sidebar-w); background: var(--navy);
      min-height: 100vh; position: fixed; top: 0; left: 0;
      display: flex; flex-direction: column; z-index: 50;
    }
    .sidebar-logo {
      padding: 20px 16px 16px;
      border-bottom: 1px solid rgba(255,255,255,0.1);
      text-decoration: none; display: block; overflow: hidden;
    }
    .sidebar-logo .wordmark {
      font-family: var(--font-display); font-size: 26px;
      font-weight: 800; color: #fff; letter-spacing: -1px;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block;
    }
    .sidebar-logo .dot { color: var(--accent); }
    .sidebar-logo .underline {
      height: 3px; width: 72%; margin-top: 5px;
      background: linear-gradient(90deg, var(--accent), var(--accent2), transparent);
      border-radius: 99px;
    }
    .sidebar-sections { flex: 1; overflow-y: auto; padding: 6px 0; }
    .sidebar-section { padding: 10px 10px 4px; }
    /* ── CONFIRM MODAL ─────────────────────────────────── */
  #solvenin-confirm-overlay {
    display:none; position:fixed; inset:0; background:rgba(0,0,0,0.5);
    z-index:9999; align-items:center; justify-content:center;
  }
  #solvenin-confirm-overlay.open { display:flex; }
  #solvenin-confirm-box {
    background:#fff; border-radius:16px; padding:28px 32px; max-width:400px;
    width:90%; box-shadow:0 20px 60px rgba(0,0,0,0.2);
  }
  #solvenin-confirm-title {
    font-size:16px; font-weight:700; color:#0f172a; margin-bottom:8px;
  }
  #solvenin-confirm-msg {
    font-size:14px; color:#64748b; margin-bottom:24px; line-height:1.5;
  }
  #solvenin-confirm-btns {
    display:flex; gap:10px; justify-content:flex-end;
  }
  #solvenin-confirm-btns button {
    padding:8px 20px; border-radius:8px; border:none; font-size:14px;
    font-weight:600; cursor:pointer; transition:all .15s;
  }
  #solvenin-confirm-cancel {
    background:#f1f5f9; color:#64748b;
  }
  #solvenin-confirm-ok {
    background:#ef4444; color:#fff;
  }
  #solvenin-confirm-ok:hover { background:#dc2626; }

  .sidebar-section-label {
      font-size: 9px; font-weight: 700; letter-spacing: 2px;
      text-transform: uppercase; color: rgba(255,255,255,0.45);
      padding: 0 8px; margin-bottom: 4px;
    }
    .nav-item {
      display: flex; align-items: center; gap: 9px;
      padding: 7px 10px; border-radius: 8px; cursor: pointer;
      transition: all .15s; margin-bottom: 1px;
      text-decoration: none; color: rgba(255,255,255,0.85);
      font-size: 12.5px; font-weight: 500;
    }
    .nav-item:hover { background: rgba(255,255,255,0.1); color: #fff; }
    .nav-item.active { background: rgba(96,165,250,0.2); color: #fff; font-weight: 600; }
    .nav-item.active .nav-icon { color: var(--accent); }
    .nav-icon { font-size: 14px; width: 18px; text-align: center; flex-shrink: 0; }
    .nav-badge {
      margin-left: auto; background: rgba(255,255,255,0.2);
      color: #fff; font-size: 10px; font-weight: 700;
      padding: 2px 7px; border-radius: 99px;
    }
    .sidebar-footer {
      padding: 10px;
      border-top: 1px solid rgba(255,255,255,0.1);
    }
    /* Company switcher */
    .company-switcher {
      display: flex; align-items: center; gap: 10px;
      padding: 8px 10px; margin: 0 0 4px;
      border-radius: 8px; cursor: pointer;
      background: rgba(255,255,255,0.08);
      border: 1px solid rgba(255,255,255,0.12);
      transition: background .15s;
    }
    .company-switcher:hover { background: rgba(96,165,250,0.15); }
    .company-icon { font-size: 16px; flex-shrink: 0; }
    .company-info { flex: 1; min-width: 0; }
    .company-name {
      font-size: 12px; font-weight: 700; color: #fff;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .company-plan { font-size: 10px; color: rgba(255,255,255,0.45); text-transform: uppercase; letter-spacing: .5px; }
    .company-chevron { color: rgba(255,255,255,0.4); font-size: 14px; flex-shrink: 0; }
    .company-menu {
      margin: 0 0 6px; border-radius: 10px;
      background: rgba(255,255,255,0.97);
      border: 1px solid rgba(255,255,255,0.2);
      box-shadow: 0 8px 24px rgba(0,0,0,0.2);
      overflow: hidden;
    }
    .company-menu-item {
      display: flex; align-items: center; gap: 10px;
      padding: 8px 12px; cursor: pointer; transition: background .15s;
    }
    .company-menu-item:hover { background: #f8fafc; }
    .company-menu-item.active { background: #eff6ff; }
    .company-menu-item .c-dot {
      width: 7px; height: 7px; border-radius: 50%;
      background: #cbd5e1; flex-shrink: 0;
    }
    .company-menu-item.active .c-dot { background: #60a5fa; }
    .company-menu-item .c-label {
      font-size: 12px; font-weight: 600; color: #334155;
      flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .company-menu-item .c-role { font-size: 10px; color: #94a3b8; }
    .company-menu-footer { border-top: 1px solid #f1f5f9; padding: 6px; }
    .company-menu-footer button {
      width: 100%; padding: 7px; border-radius: 7px;
      border: 1px dashed #cbd5e1; background: none; color: #64748b;
      font-size: 11px; cursor: pointer; transition: all .15s;
    }
    .company-menu-footer button:hover { background: #eff6ff; color: #60a5fa; border-color: #60a5fa; }
    /* User card */
    .user-card {
      display: flex; align-items: center; gap: 10px;
      padding: 8px 10px; border-radius: 10px; cursor: pointer; transition: all .15s;
    }
    .user-card:hover { background: rgba(255,255,255,0.08); }
    .user-avatar {
      width: 32px; height: 32px; border-radius: 9px;
      background: rgba(96,165,250,0.35);
      display: flex; align-items: center; justify-content: center;
      font-weight: 700; color: #fff; font-size: 13px; flex-shrink: 0;
    }
    .user-name { font-size: 12px; font-weight: 600; color: #fff; }
    .user-plan { font-size: 10px; color: rgba(255,255,255,0.45); margin-top: 1px; }
    .user-menu-btn { margin-left: auto; color: rgba(255,255,255,0.25); font-size: 18px; }
    /* New company modal */
    .new-company-modal {
      display: none; position: fixed; inset: 0;
      background: rgba(0,0,0,0.5); z-index: 9999;
      align-items: center; justify-content: center;
    }
    .new-company-modal.open { display: flex; }
    .new-company-box {
      background: #fff; border-radius: 16px;
      padding: 28px; width: 380px; box-shadow: 0 20px 60px rgba(0,0,0,0.2);
    }
    .new-company-box h3 { font-size: 18px; font-weight: 700; color: #1e293b; margin-bottom: 6px; }
    .new-company-box p { font-size: 13px; color: #64748b; margin-bottom: 20px; }
    .new-company-box input {
      width: 100%; padding: 10px 12px; border-radius: 8px;
      border: 1.5px solid #e2e8f0; font-size: 14px; margin-bottom: 16px;
      outline: none; transition: border .15s;
    }
    .new-company-box input:focus { border-color: #60a5fa; }
    .new-company-box .btn-row { display: flex; gap: 10px; justify-content: flex-end; }
    .new-company-box .btn-cancel {
      padding: 8px 18px; border-radius: 8px; border: 1.5px solid #e2e8f0;
      background: none; color: #64748b; font-size: 13px; cursor: pointer;
    }
    .new-company-box .btn-create {
      padding: 8px 18px; border-radius: 8px; border: none;
      background: #60a5fa; color: #fff; font-size: 13px;
      font-weight: 600; cursor: pointer;
    }
    .new-company-box .btn-create:hover { background: #3b82f6; }
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

  // Global confirm dialog (replaces browser confirm())
  // Re-render sidebar on language change
  document.addEventListener('langChanged', function() {
    const sb = document.getElementById('sidebar');
    if (sb) {
      const prev = sb.innerHTML;
      sb.innerHTML = buildHTML();
      // Re-attach supabase data after re-render
      loadSidebarData();
    }
  });

  window.showConfirm = function(message, title) {
    return new Promise((resolve, reject) => {
      const overlay = document.getElementById('solvenin-confirm-overlay');
      const msg = document.getElementById('solvenin-confirm-msg');
      const titleEl = document.getElementById('solvenin-confirm-title');
      const okBtn = document.getElementById('solvenin-confirm-ok');
      if (!overlay) { resolve(window.confirm(message)); return; }
      titleEl.textContent = title || 'Confirm';
      msg.textContent = message;
      overlay.classList.add('open');
      window._confirmReject = () => { resolve(false); };
      okBtn.onclick = () => {
        overlay.classList.remove('open');
        resolve(true);
      };
    });
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
  const NAV = [
    {
      labelKey: 'nav_group_main',
      items: [
        { icon: '📦', key: 'nav_inventory',   href: 'inventory.html' },
        { icon: '💰', key: 'nav_sales',        href: 'sales.html' },
        { icon: '🛒', key: 'nav_purchasing',   href: 'purchasing.html' },
        { icon: '🏭', key: 'nav_production',   href: 'production.html' },
      ]
    },
    {
      labelKey: 'nav_group_finance',
      items: [
        { icon: '🏦', key: 'nav_cashbank',     href: 'cashbank.html' },
        { icon: '📒', key: 'nav_accounting',   href: 'accounting.html' },
        { icon: '📊', key: 'nav_reports',      href: '#' },
      ]
    },
    {
      labelKey: 'nav_group_management',
      items: [
        { icon: '👥', key: 'nav_hr',           href: 'hr.html' },
        { icon: '🚚', key: 'nav_shipping',     href: '#' },
        { icon: '📅', key: 'nav_projects',     href: '#' },
        { icon: '🔧', key: 'nav_maintenance',  href: '#' },
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

  /* ── HELPERS ─────────────────────────────────────────────── */
  function currentPage() {
    return window.location.pathname.split('/').pop() || 'dashboard.html';
  }

  function injectCSS() {
    const style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  function buildHTML() {
    const page = currentPage();
    let sectionsHTML = '';
    const _t = window.t || (k => k);
    NAV.forEach(section => {
      let itemsHTML = section.items.map(item => {
        const active = item.href !== '#' && page === item.href ? 'active' : '';
        const label = _t(item.key) || item.key;
        return `<a class="nav-item ${active}" href="${item.href}">
          <span class="nav-icon">${item.icon}</span> ${label}
        </a>`;
      }).join('\n');
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

    // Use existing placeholder or create new
    let sidebar = document.getElementById('sidebar');
    if (!sidebar) {
      sidebar = document.createElement('aside');
      sidebar.className = 'sidebar';
      sidebar.id = 'sidebar';
      document.body.insertBefore(sidebar, document.body.firstChild);
    }
    sidebar.innerHTML = buildHTML();
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

      // User info
      const email = user.email || '';
      const initials = email.substring(0, 2).toUpperCase();
      const nameEl = document.getElementById('sb-user-name');
      const avatarEl = document.getElementById('sb-user-avatar');
      if (nameEl) nameEl.textContent = email;
      if (avatarEl) avatarEl.textContent = initials;

      // Company
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

      // All companies for switcher
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
  window.sidebarToggleCompanyMenu = function () {
    const menu = document.getElementById('sb-company-menu');
    if (menu) menu.style.display = menu.style.display === 'none' ? 'block' : 'none';
  };

  window.sidebarSwitchCompany = async function (id) {
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

  window.sidebarOpenNewCompany = function () {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.add('open');
    const menu = document.getElementById('sb-company-menu');
    if (menu) menu.style.display = 'none';
  };

  window.sidebarCloseNewCompany = function () {
    const modal = document.getElementById('sb-new-company-modal');
    if (modal) modal.classList.remove('open');
  };

  window.sidebarCreateCompany = async function () {
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

  /* ── INIT ────────────────────────────────────────────────── */
  function init() {
    // mount() already called synchronously - just load data
    const wait = setInterval(() => {
      if (window._supabase || window.supabase) {
        clearInterval(wait);
        loadSidebarData();
      }
    }, 100);
    setTimeout(() => clearInterval(wait), 5000);
  }

  // Mount immediately if DOM ready, otherwise on DOMContentLoaded
  function tryMount() {
    if (document.body) {
      mount();
      window._sidebarMounted = true;
      document.dispatchEvent(new Event('sidebarMounted'));
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      tryMount();
      const wait = setInterval(() => {
        if (window._supabase || window.supabase) {
          clearInterval(wait);
          loadSidebarData();
        }
      }, 100);
      setTimeout(() => clearInterval(wait), 5000);
    });
  } else {
    tryMount();
    const wait = setInterval(() => {
      if (window._supabase || window.supabase) {
        clearInterval(wait);
        loadSidebarData();
      }
    }, 100);
    setTimeout(() => clearInterval(wait), 5000);
  }

})();
