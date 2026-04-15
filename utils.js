/* utils.js — Solvenin global utilities
   Include AFTER i18n.js, BEFORE page-specific scripts
*/

// ===== DOUBLE-SUBMIT GUARD =====
// Wraps any async button handler: disables button, shows spinner, re-enables after.
window.withLoading = function(btn, asyncFn) {
  if (!btn || btn.disabled) return;
  const orig = btn.innerHTML;
  const isDark = !btn.classList.contains('btn-primary');
  btn.disabled = true;
  btn.innerHTML = `<span class="btn-spinner${isDark?' dark':''}"></span> ${orig}`;
  asyncFn().catch(e => { console.error(e); }).finally(() => {
    btn.disabled = false;
    btn.innerHTML = orig;
  });
};

// Per-caller double-submit guard with auto-reset safety net.
// Usage: if (submitting()) return;
// The flag auto-resets after 10 seconds as a safety net against stuck state.
// Each caller gets its own flag based on the call stack.
window.submitting = (function() {
  const _flags = {};
  const fn = (key) => {
    const k = key || (new Error().stack?.split('\n')[2]?.trim() || '_default');
    if (_flags[k]) return true;
    _flags[k] = true;
    setTimeout(() => { delete _flags[k]; }, 10000); // safety net
    return false;
  };
  fn.reset = (key) => {
    if (key) { delete _flags[key]; return; }
    // Reset all flags
    Object.keys(_flags).forEach(k => delete _flags[k]);
  };
  return fn;
})();

// ===== ERROR MESSAGE HANDLER =====
// Maps raw DB/API errors to user-friendly localized messages.
// Never shows internal constraint names or table structure.
window.getErrorMessage = function(error) {
  const _t = (typeof t === 'function') ? t : (k => k);
  if (!error) return _t('error_general') || 'Bir hata oluştu';
  const raw = (error.message || error.toString() || '');
  const msg = raw.toLowerCase();
  // Plan-limit trigger errors (match exact error code tokens from triggers)
  const planErrors = [
    'free_plan_invoice_limit', 'free_plan_no_users', 'plan_user_limit_reached',
    'free_plan_one_company', 'standard_plan_one_company',
    'free_plan_warehouse_limit', 'free_plan_register_limit'
  ];
  for (const code of planErrors) {
    if (raw.includes(code)) return _t('error_' + code) || code;
  }
  if (msg.includes('violates foreign key constraint'))
    return _t('error_related_record') || 'Bu kayıt başka verilerle ilişkili, silinemez';
  if (msg.includes('violates unique constraint') || msg.includes('duplicate key')) {
    if (raw.includes('idx_products_barcode')) return 'Bu barkod başka bir ürüne ait';
    if (raw.includes('idx_products_sku')) return 'Bu SKU başka bir ürüne ait';
    if (raw.includes('idx_products_plu')) return 'Bu PLU kodu başka bir ürüne ait';
    if (raw.includes('idx_sales_orders_number')) return 'Bu sipariş numarası zaten kullanılıyor';
    if (raw.includes('idx_purchase_orders_number')) return 'Bu sipariş numarası zaten kullanılıyor';
    if (raw.includes('idx_warehouses_name')) return 'Bu depo adı zaten kullanılıyor';
    if (raw.includes('idx_cash_registers_name')) return 'Bu kasa adı zaten kullanılıyor';
    if (raw.includes('idx_tax_rates_name')) return 'Bu vergi oranı adı zaten kullanılıyor';
    if (raw.includes('idx_categories_name')) return 'Bu kategori adı aynı üst kategoride zaten var';
    return _t('error_duplicate') || 'Bu kayıt zaten mevcut';
  }
  if (msg.includes('row-level security') || msg.includes('rls'))
    return _t('error_permission') || 'Bu işlem için yetkiniz yok';
  if (msg.includes('violates check constraint'))
    return _t('error_invalid_value') || 'Geçersiz değer';
  if (msg.includes('not-null') || msg.includes('null value'))
    return _t('error_required_field') || 'Zorunlu alan boş bırakılamaz';
  if (msg.includes('jwt') || msg.includes('token') || msg.includes('auth'))
    return _t('error_session_expired') || 'Oturum süresi doldu, lütfen tekrar giriş yapın';
  if (msg.includes('networkerror') || msg.includes('failed to fetch') || msg.includes('load failed'))
    return _t('error_network') || 'Bağlantı hatası, lütfen tekrar deneyin';
  return _t('error_general') || 'Bir hata oluştu, lütfen tekrar deneyin';
};

// ===== NUMBER FORMATTING =====
function getNumLocale() {
  const lang = (typeof detectLang === 'function') ? detectLang() : 'en';
  return ['tr','de','fr','es','pt','ru'].includes(lang) ? 'tr' : 'en';
}

function fmtNum(n) {
  if (n === '' || n === null || n === undefined) return '';
  const num = typeof n === 'string' ? parseNum(n) : n;
  if (isNaN(num) || num === 0) return '';
  const loc = getNumLocale();
  const hasDecimals = num % 1 !== 0;
  return num.toLocaleString(loc === 'tr' ? 'tr-TR' : 'en-US', {
    minimumFractionDigits: hasDecimals ? 2 : 0,
    maximumFractionDigits: 6
  });
}

function parseNum(s) {
  if (!s || typeof s !== 'string') return typeof s === 'number' ? s : 0;
  const loc = getNumLocale();
  if (loc === 'tr') { s = s.replace(/\./g, '').replace(',', '.'); }
  else { s = s.replace(/,/g, ''); }
  return parseFloat(s) || 0;
}

function fmtInput(el) {
  const raw = el.value;
  if (raw === '' || raw === '-') return;
  const loc = getNumLocale();
  const decSep = loc === 'tr' ? ',' : '.';
  if (raw.endsWith(decSep) || raw.endsWith(decSep + '0')) return;
}

function numFocus(el) {
  if (parseNum(el.value) === 0) el.value = '';
  else el.select();
}

function numBlur(el) {
  const n = parseNum(el.value);
  el.value = n ? fmtNum(n) : '';
}

// ===== CURRENCY FORMATTING =====
function _fmtLocale() {
  const l = (typeof detectLang === 'function') ? detectLang() : 'en';
  return ['tr','de','fr','es','pt','ru'].includes(l) ? 'tr-TR' : 'en-US';
}

function fmt(amount) {
  const sym = window.getCurrencySymbol ? window.getCurrencySymbol() : '$';
  return sym + parseFloat(amount || 0).toLocaleString(_fmtLocale(), {
    minimumFractionDigits: 2, maximumFractionDigits: 2
  });
}

function fmtShort(amount) {
  const sym = window.getCurrencySymbol ? window.getCurrencySymbol() : '$';
  const n = parseFloat(amount || 0);
  const loc = _fmtLocale();
  if (n >= 1000000) return sym + (n / 1000000).toFixed(1) + 'M';
  if (n >= 1000) return sym + (n / 1000).toFixed(1) + 'K';
  return sym + n.toLocaleString(loc, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// ===== DATE FORMATTING =====
function fmtDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr + (dateStr.includes('T') ? '' : 'T00:00:00'));
  if (isNaN(d)) return dateStr;
  const lang = (typeof detectLang === 'function') ? detectLang() : 'en';
  const locale = lang === 'tr' ? 'tr-TR' : lang === 'de' ? 'de-DE' : lang === 'fr' ? 'fr-FR' : 'en-GB';
  return d.toLocaleDateString(locale, { day: '2-digit', month: 'short', year: 'numeric' });
}

// ===== KEYBOARD: Enter navigates to next field =====
document.addEventListener('keydown', function(e) {
  if (e.key !== 'Enter') return;
  const el = document.activeElement;
  if (!el || el.tagName === 'TEXTAREA' || el.tagName === 'BUTTON') return;
  if (el.tagName === 'SELECT') return;
  // Skip if inside QA dropdown
  if (el.closest && el.closest('.qa-wrap')) return;
  // Skip if custom handler
  if (el.dataset.col) return;
  if (el.tagName === 'INPUT') {
    e.preventDefault();
    const form = el.closest('form, .form-grid, .modal-body, .content, #order-form-view');
    if (!form) return;
    const inputs = [...form.querySelectorAll('input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled])')];
    const idx = inputs.indexOf(el);
    if (idx >= 0 && idx < inputs.length - 1) {
      inputs[idx + 1].focus();
    }
  }
});

// ===== SELECT ALL ON FOCUS for number inputs =====
document.addEventListener('focusin', function(e) {
  const el = e.target;
  if (el.tagName === 'INPUT' && el.classList.contains('num-input')) {
    setTimeout(() => el.select(), 0);
  }
});

// ===== COMPANY LOGO HELPER (for PDF generators) =====
// Returns the cached company logo data URL (synchronous), or null.
// Pages set this cache via sidebar.js loadSidebarData / settings save.
window.getCompanyLogo = function(companyId) {
  try {
    const cid = companyId || localStorage.getItem('currentCompanyId');
    if (!cid) return null;
    const url = localStorage.getItem('solvenin_company_logo_'+cid);
    return url || null;
  } catch (e) { return null; }
};

// Add the company logo to a jsPDF document. Returns the height used so the
// caller can offset following content. Width = max 50pt, preserves aspect.
// Returns 0 if no logo or any failure (caller should fall back to text header).
window.addLogoToPdf = function(doc, x, y, maxWidth, maxHeight) {
  try {
    const logo = window.getCompanyLogo();
    if (!logo) return 0;
    if (!logo.startsWith('data:image/')) return 0;
    const isPng = logo.startsWith('data:image/png');
    const isJpeg = logo.startsWith('data:image/jpeg') || logo.startsWith('data:image/jpg');
    const isWebp = logo.startsWith('data:image/webp');
    const isSvg = logo.startsWith('data:image/svg');
    if (isSvg) return 0; // jsPDF can't render SVG
    const fmt = isPng ? 'PNG' : isJpeg ? 'JPEG' : isWebp ? 'WEBP' : 'PNG';
    const w = maxWidth || 40;
    const h = maxHeight || 40;
    doc.addImage(logo, fmt, x, y, w, h, undefined, 'FAST');
    return h;
  } catch (e) {
    console.warn('addLogoToPdf failed:', e);
    return 0;
  }
};

// ===== GLOBAL THOUSAND-SEPARATOR ENHANCER =====
// Converts every <input type="number"> (and .num-input) to a text input with
// live thousand-separator formatting AND overrides el.value so existing
// parseFloat(el.value) calls keep working transparently across all pages.
(function() {
  if (window.__numEnhancerInstalled) return;
  window.__numEnhancerInstalled = true;

  const nativeDesc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  const nativeGet = nativeDesc.get;
  const nativeSet = nativeDesc.set;

  function rawText(el) { return nativeGet.call(el); }
  function setRaw(el, v) { nativeSet.call(el, v); }

  // Should this input be enhanced?
  function isCandidate(el) {
    if (!el || el.tagName !== 'INPUT') return false;
    if (el._numEnhanced) return false;
    if (el.dataset.noNumFormat === '1') return false;
    if (el.classList.contains('num-input')) return true;
    if (el.type === 'number') return true;
    return false;
  }

  function localeSeparators() {
    const loc = (typeof getNumLocale === 'function') ? getNumLocale() : 'en';
    return loc === 'tr'
      ? { dec: ',', grp: '.' }
      : { dec: '.', grp: ',' };
  }

  // Format text-as-typed without losing user intent (trailing dec sep, trailing zeros after dec)
  function formatTyped(text) {
    const { dec, grp } = localeSeparators();
    if (text == null) return '';
    let s = String(text);
    // Allow only digits, separators, and leading minus
    let neg = false;
    if (s.startsWith('-')) { neg = true; s = s.slice(1); }
    // Strip all chars except digits and separators
    s = s.replace(new RegExp('[^0-9' + (dec === '.' ? '\\.' : ',') + ']', 'g'), '');
    // Split on decimal sep — only first occurrence
    const idx = s.indexOf(dec);
    let intPart = idx >= 0 ? s.slice(0, idx) : s;
    let decPart = idx >= 0 ? s.slice(idx + 1).replace(new RegExp('\\' + dec, 'g'), '') : null;
    // Strip leading zeros in int part (but keep at least one)
    intPart = intPart.replace(/^0+(?=\d)/, '');
    if (intPart === '') intPart = '0';
    // Group thousands
    const grouped = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, grp);
    let out = grouped;
    if (idx >= 0) out += dec + (decPart || '');
    if (neg) out = '-' + out;
    return out;
  }

  // Parse formatted text → numeric string for el.value
  function toNumeric(text) {
    if (text == null || text === '') return '';
    const { dec, grp } = localeSeparators();
    let s = String(text);
    // Remove grouping char
    s = s.split(grp).join('');
    // Replace decimal sep with '.'
    if (dec !== '.') s = s.replace(dec, '.');
    // Drop any other non-numeric noise
    s = s.replace(/[^\d.\-]/g, '');
    if (s === '' || s === '-' || s === '.' || s === '-.') return '';
    return s;
  }

  function enhance(el) {
    if (!isCandidate(el)) return;
    el._numEnhanced = true;

    // Switch to text so we can show separators
    if (el.type === 'number') {
      try {
        el.type = 'text';
        if (!el.getAttribute('inputmode')) el.setAttribute('inputmode', 'decimal');
        if (!el.getAttribute('autocomplete')) el.setAttribute('autocomplete', 'off');
      } catch(e) {}
    }

    // Override value getter/setter on this element
    Object.defineProperty(el, 'value', {
      configurable: true,
      get() {
        return toNumeric(rawText(this));
      },
      set(v) {
        if (v === '' || v === null || v === undefined) {
          setRaw(this, '');
          return;
        }
        // Accept either a Number or a string in either format
        let num;
        if (typeof v === 'number') num = v;
        else {
          const t = String(v).trim();
          if (t === '') { setRaw(this, ''); return; }
          // If looks already-formatted (has grouping char), strip and parse
          num = parseFloat(toNumeric(formatTyped(t)));
          if (isNaN(num)) { setRaw(this, ''); return; }
        }
        if (isNaN(num)) { setRaw(this, ''); return; }
        if (num === 0) { setRaw(this, ''); return; }
        // Format with grouping; preserve up to 6 decimals from input
        const { dec, grp } = localeSeparators();
        const hasDec = num % 1 !== 0;
        const parts = (Math.abs(num)).toFixed(hasDec ? Math.min(6, (String(num).split('.')[1]||'').length) : 0).split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, grp);
        let out = parts.join(dec);
        if (num < 0) out = '-' + out;
        setRaw(this, out);
      }
    });

    // Format as the user types
    el.addEventListener('input', function(ev) {
      // Skip if synthetic event from our own setRaw call
      const text = rawText(el);
      if (text === '') return;
      const start = el.selectionStart;
      const before = text;
      const beforeLen = before.length;
      const formatted = formatTyped(before);
      if (formatted !== before) {
        setRaw(el, formatted);
        // Best-effort cursor restore: keep distance from end stable
        const afterLen = formatted.length;
        const newPos = Math.max(0, (start || 0) + (afterLen - beforeLen));
        try { el.setSelectionRange(newPos, newPos); } catch(e) {}
      }
    });

    // Reformat / clean up on blur (drop dangling separators)
    el.addEventListener('blur', function() {
      const text = rawText(el);
      if (!text) return;
      const numeric = toNumeric(text);
      if (numeric === '' || isNaN(parseFloat(numeric))) {
        setRaw(el, '');
        return;
      }
      // Re-set via setter to canonicalize
      el.value = parseFloat(numeric);
    });

    // Initialize with existing value (e.g. when JS sets value before enhancement)
    const existing = rawText(el);
    if (existing !== '' && existing != null) {
      setRaw(el, formatTyped(existing));
    }
  }

  function scan(root) {
    if (!root) return;
    if (root.nodeType === 1) {
      if (isCandidate(root)) enhance(root);
      const all = root.querySelectorAll && root.querySelectorAll('input[type="number"], input.num-input');
      if (all) all.forEach(enhance);
    }
  }

  // Initial scan
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => scan(document.body));
  } else {
    scan(document.body);
  }

  // Observe DOM changes for dynamically-added inputs (modal forms etc.)
  const observer = new MutationObserver((mutations) => {
    for (const m of mutations) {
      m.addedNodes && m.addedNodes.forEach(scan);
    }
  });
  if (document.body) observer.observe(document.body, { childList: true, subtree: true });
  else document.addEventListener('DOMContentLoaded', () => observer.observe(document.body, { childList: true, subtree: true }));

  // Public API
  window.numFormat = formatTyped;
  window.numParse = (t) => { const n = parseFloat(toNumeric(t)); return isNaN(n) ? 0 : n; };
})();
