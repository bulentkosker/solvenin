// ============================================================
// i18n/loader.js — Solvenin i18n loader (replaces legacy i18n.js)
// ============================================================
// Loads only the active language (+ en fallback) instead of bundling
// all 16 locales into one 836KB file. Active language file is injected
// via document.write so it parses BEFORE any page init runs and t()/
// applyTranslations() can be called synchronously by callers.
//
// API surface kept identical to the legacy i18n.js:
//   - window.T            (populated by per-lang scripts)
//   - SUPPORTED_LANGS, LANG_META, LANG_MAPPING
//   - detectLang(), t(), applyTranslations()
//   - setLang(), updateLangSwitcherUI(), toggleLangMenu(), selectLang()
//   - saveLangToProfile(), loadLangFromProfile()
//   - formatDate(), formatNumber(), DATE_FORMATS, NUMBER_FORMATS
// ============================================================

const SUPPORTED_LANGS = ['en','tr','de','fr','es','ar','zh','ru','pt','ja','kz','kg','uz','tm','az','pl'];

const LANG_META = {
  en: { code:'EN', name:'English',         dir:'ltr' },
  tr: { code:'TR', name:'Türkçe',          dir:'ltr' },
  de: { code:'DE', name:'Deutsch',         dir:'ltr' },
  fr: { code:'FR', name:'Français',        dir:'ltr' },
  es: { code:'ES', name:'Español',         dir:'ltr' },
  ar: { code:'AR', name:'العربية',          dir:'rtl' },
  zh: { code:'ZH', name:'中文',             dir:'ltr' },
  ru: { code:'RU', name:'Русский',         dir:'ltr' },
  pt: { code:'PT', name:'Português',       dir:'ltr' },
  ja: { code:'JA', name:'日本語',           dir:'ltr' },
  kz: { code:'KZ', name:'Қазақ тілі',      dir:'ltr' },
  kg: { code:'KG', name:'Кыргыз тили',     dir:'ltr' },
  uz: { code:'UZ', name:"O'zbek tili",     dir:'ltr' },
  tm: { code:'TM', name:'Türkmen dili',    dir:'ltr' },
  az: { code:'AZ', name:'Azərbaycan dili', dir:'ltr' },
  pl: { code:'PL', name:'Polski',          dir:'ltr' },
};

// Browser locale → app lang mapping (handles ISO 639-1 codes that differ from project codes)
const LANG_MAPPING = {
  'zh':'zh','zh-cn':'zh','zh-tw':'zh','zh-hk':'zh','zh-sg':'zh',
  'pt':'pt','pt-br':'pt','pt-pt':'pt',
  'ar':'ar','ar-sa':'ar','ar-ae':'ar','ar-eg':'ar','ar-kw':'ar','ar-qa':'ar',
  'ar-bh':'ar','ar-iq':'ar','ar-jo':'ar','ar-lb':'ar','ar-ly':'ar','ar-ma':'ar',
  'ar-om':'ar','ar-sy':'ar','ar-tn':'ar','ar-ye':'ar','ar-dz':'ar',
  'kk':'kz','kk-kz':'kz', 'ky':'kg','ky-kg':'kg', 'tk':'tm','tk-tm':'tm',
  'uz':'uz','uz-uz':'uz','uz-latn':'uz','uz-cyrl':'uz',
  'az':'az','az-az':'az','az-latn':'az','az-cyrl':'az',
};

function detectLang() {
  // Migrate legacy codes
  ['solvenin_lang','lang'].forEach(k => {
    if (localStorage.getItem(k) === 'tk') localStorage.setItem(k, 'tm');
    if (localStorage.getItem(k) === 'ky') localStorage.setItem(k, 'kg');
  });
  const saved = localStorage.getItem('solvenin_lang');
  if (saved && SUPPORTED_LANGS.includes(saved)) return saved;
  const browserLang = (navigator.language || navigator.userLanguage || 'en').toLowerCase();
  const langCode = browserLang.split('-')[0];
  if (SUPPORTED_LANGS.includes(langCode)) return langCode;
  if (LANG_MAPPING[browserLang]) return LANG_MAPPING[browserLang];
  if (LANG_MAPPING[langCode]) return LANG_MAPPING[langCode];
  return 'en';
}

window.T = window.T || {};

// ---- Sync-load active language + en fallback ----------------------
// document.write of a <script> tag blocks parsing until the script
// is fetched + executed. Must run BEFORE the page fires DOMContentLoaded
// so t()/applyTranslations() see populated translations on first use.
(function(){
  const lang = detectLang();
  // Resolve loader.js's own URL → use as base for sibling lang files.
  let base = '';
  try {
    const scripts = document.getElementsByTagName('script');
    for (let i = 0; i < scripts.length; i++) {
      const src = scripts[i].src || '';
      if (src.endsWith('/i18n/loader.js') || src.endsWith('i18n/loader.js')) {
        base = src.replace(/loader\.js(\?.*)?$/, '');
        break;
      }
    }
    if (!base) base = 'i18n/';
  } catch(_) { base = 'i18n/'; }
  const inject = (l) => {
    if (window.T[l]) return; // already loaded
    document.write('<script src="' + base + l + '.js"><' + '/script>');
  };
  inject(lang);
  if (lang !== 'en') inject('en'); // fallback always present
})();

const _missingKeys = new Set();
function t(key) {
  const lang = detectLang();
  const val = (window.T[lang] && window.T[lang][key]) || (window.T['en'] && window.T['en'][key]);
  if (!val && !_missingKeys.has(lang+':'+key)) {
    _missingKeys.add(lang+':'+key);
    if (window.console && console.warn) console.warn('[i18n] missing key "' + key + '" for lang "' + lang + '"');
  }
  return val || key;
}

function applyTranslations() {
  const lang = detectLang();
  const translations = window.T[lang] || window.T['en'] || {};
  const enT = window.T['en'] || {};
  const lookup = (key) => translations[key] !== undefined ? translations[key] : enT[key];
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    const val = lookup(key);
    if (val !== undefined) {
      if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') el.placeholder = val;
      else el.textContent = val;
    }
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    const val = lookup(el.getAttribute('data-i18n-placeholder'));
    if (val !== undefined) el.placeholder = val;
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    const val = lookup(el.getAttribute('data-i18n-title'));
    if (val !== undefined) el.title = val;
  });
  document.querySelectorAll('[data-i18n-tooltip]').forEach(el => {
    const val = lookup(el.getAttribute('data-i18n-tooltip'));
    if (val !== undefined) el.setAttribute('data-tooltip', val);
  });
  try {
    const dir = LANG_META[lang] && LANG_META[lang].dir || 'ltr';
    document.documentElement.setAttribute('dir', dir);
    document.documentElement.setAttribute('lang', lang);
  } catch(_) {}
  if (typeof updateLangSwitcherUI === 'function') updateLangSwitcherUI(lang);
}

function ensureLangLoaded(lang, cb) {
  if (window.T[lang]) { cb && cb(); return; }
  const s = document.createElement('script');
  s.src = (function(){
    const scripts = document.getElementsByTagName('script');
    for (let i = 0; i < scripts.length; i++) {
      const src = scripts[i].src || '';
      if (src.endsWith('loader.js') || /\/i18n\/[a-z]{2}\.js/.test(src)) {
        return src.replace(/[^/]+\.js$/, lang + '.js');
      }
    }
    return 'i18n/' + lang + '.js';
  })();
  s.onload = () => cb && cb();
  document.head.appendChild(s);
}

function setLang(lang) {
  if (!SUPPORTED_LANGS.includes(lang)) return;
  localStorage.setItem('solvenin_lang', lang);
  // Lazy-load the new lang file if it isn't yet in window.T
  ensureLangLoaded(lang, () => {
    applyTranslations();
    document.dispatchEvent(new CustomEvent('langChanged', { detail: { lang } }));
  });
}

function updateLangSwitcherUI(lang) {
  const meta = LANG_META[lang] || LANG_META['en'];
  const codeEl = document.getElementById('lang-code');
  const nameEl = document.getElementById('lang-name');
  if (codeEl) codeEl.textContent = meta.code;
  if (nameEl) nameEl.textContent = meta.name;
  document.querySelectorAll('.lang-opt').forEach(opt => {
    opt.classList.toggle('active', opt.dataset.lang === lang);
  });
}

function toggleLangMenu() {
  const menu = document.getElementById('lang-menu');
  const btn = document.getElementById('lang-switcher');
  if (!menu) return;
  const isOpen = menu.style.display === 'block';
  menu.style.display = isOpen ? 'none' : 'block';
  if (btn) btn.classList.toggle('open', !isOpen);
}

function selectLang(lang) {
  setLang(lang);
  const menu = document.getElementById('lang-menu');
  if (menu) menu.style.display = 'none';
  const btn = document.getElementById('lang-switcher');
  if (btn) btn.classList.remove('open');
  saveLangToProfile(lang);
}

async function saveLangToProfile(lang) {
  try {
    const sb = window._supabase || window.supabase;
    if (!sb || !sb.auth) return;
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return;
    await sb.from('profiles').update({ preferred_language: lang }).eq('id', user.id);
  } catch (_) {}
}

async function loadLangFromProfile() {
  try {
    const sb = window._supabase || window.supabase;
    if (!sb || !sb.auth) return;
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return;
    const { data } = await sb.from('profiles').select('preferred_language').eq('id', user.id).single();
    const lang = data && data.preferred_language;
    if (lang && SUPPORTED_LANGS.includes(lang)) {
      const current = localStorage.getItem('solvenin_lang');
      if (current !== lang) {
        localStorage.setItem('solvenin_lang', lang);
        setLang(lang);
      }
    }
  } catch (_) {}
}

if (typeof window !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => setTimeout(loadLangFromProfile, 800));
}

// Close lang dropdown on outside click
document.addEventListener('click', function(e) {
  const wrap = document.getElementById('lang-switcher-wrap') || document.getElementById('lang-switcher');
  if (!wrap) return;
  if (!wrap.contains(e.target)) {
    const menu = document.getElementById('lang-menu');
    if (menu) menu.style.display = 'none';
    const btn = document.getElementById('lang-switcher');
    if (btn) btn.classList.remove('open');
  }
});

// ---- Locale formatters (ported from legacy i18n.js) ----------------
const DATE_FORMATS = {
  tr:'DD.MM.YYYY', ru:'DD.MM.YYYY', kz:'DD.MM.YYYY', kg:'DD.MM.YYYY',
  uz:'DD.MM.YYYY', tm:'DD.MM.YYYY', az:'DD.MM.YYYY', de:'DD.MM.YYYY',
  fr:'DD/MM/YYYY', en:'MM/DD/YYYY', es:'DD/MM/YYYY', pl:'DD.MM.YYYY',
  ar:'DD/MM/YYYY', zh:'YYYY年MM月DD日', pt:'DD/MM/YYYY', ja:'YYYY/MM/DD'
};
const NUMBER_FORMATS = {
  tr:{decimal:',',thousands:'.'}, en:{decimal:'.',thousands:','},
  ru:{decimal:',',thousands:' '}, kz:{decimal:',',thousands:' '},
  kg:{decimal:',',thousands:' '}, uz:{decimal:',',thousands:' '},
  tm:{decimal:',',thousands:' '}, az:{decimal:',',thousands:'.'},
  de:{decimal:',',thousands:'.'}, fr:{decimal:',',thousands:' '},
  es:{decimal:',',thousands:'.'}, pl:{decimal:',',thousands:' '},
  ar:{decimal:'.',thousands:','}, zh:{decimal:'.',thousands:','},
  pt:{decimal:',',thousands:'.'}, ja:{decimal:'.',thousands:','}
};
function formatDate(dateInput, lang) {
  if (!dateInput) return '';
  const d = (dateInput instanceof Date) ? dateInput : new Date(dateInput);
  if (isNaN(d.getTime())) return '';
  const L = lang || detectLang();
  const fmt = DATE_FORMATS[L] || DATE_FORMATS.en;
  const DD = String(d.getDate()).padStart(2,'0');
  const MM = String(d.getMonth()+1).padStart(2,'0');
  const YYYY = d.getFullYear();
  return fmt.replace('DD',DD).replace('MM',MM).replace('YYYY',YYYY);
}
function formatNumber(num, lang, decimals) {
  if (num === null || num === undefined || num === '' || isNaN(num)) return '';
  const L = lang || detectLang();
  const f = NUMBER_FORMATS[L] || NUMBER_FORMATS.en;
  const dec = (decimals === undefined) ? 2 : decimals;
  const parts = Number(num).toFixed(dec).split('.');
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, f.thousands);
  return parts.length > 1 ? parts.join(f.decimal) : parts[0];
}

// Expose helpers on window for legacy code paths.
if (typeof window !== 'undefined') {
  window.formatDate = formatDate;
  window.formatNumber = formatNumber;
  window.DATE_FORMATS = DATE_FORMATS;
  window.NUMBER_FORMATS = NUMBER_FORMATS;
  window.detectLang = detectLang;
  window.t = t;
  window.applyTranslations = applyTranslations;
  window.setLang = setLang;
  window.updateLangSwitcherUI = updateLangSwitcherUI;
  window.toggleLangMenu = toggleLangMenu;
  window.selectLang = selectLang;
  window.SUPPORTED_LANGS = SUPPORTED_LANGS;
  window.LANG_META = LANG_META;
  window.LANG_MAPPING = LANG_MAPPING;
}
