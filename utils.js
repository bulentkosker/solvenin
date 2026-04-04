/* utils.js — Solvenin global utilities
   Include AFTER i18n.js, BEFORE page-specific scripts
*/

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
