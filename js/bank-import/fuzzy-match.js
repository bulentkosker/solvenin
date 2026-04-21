/**
 * Bank Import — Fuzzy Name Matching
 *
 * Normalization + Cyrillic↔Latin transliteration + token-aware similarity.
 * Works in browser (window.BankImportFuzzy) and Node (module.exports).
 *
 * Why not Fuse.js: banking names carry punctuation, legal prefixes (ТОО, ИП,
 * ООО, LLC…), and two scripts in the same corpus. Pre-normalization matters
 * more than the scoring algorithm. A hand-tuned normalize + Levenshtein +
 * Jaccard blend scores the test fixtures better than default Fuse weights.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) module.exports = factory();
  else root.BankImportFuzzy = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Cyrillic → Latin (Russian + Kazakh).
  const CYR_TO_LAT = {
    'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo','ж':'zh',
    'з':'z','и':'i','й':'y','к':'k','л':'l','м':'m','н':'n','о':'o',
    'п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'kh','ц':'ts',
    'ч':'ch','ш':'sh','щ':'sch','ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya',
    // Kazakh-specific
    'ә':'a','ғ':'g','қ':'q','ң':'ng','ө':'o','ұ':'u','ү':'u','һ':'h','і':'i'
  };

  // Turkish diacritics (case-folded).
  const TR_MAP = {
    'ş':'s','ı':'i','ğ':'g','ü':'u','ö':'o','ç':'c','â':'a','î':'i','û':'u'
  };

  // Legal-entity prefixes/suffixes to strip during normalization.
  // Keep short, unambiguous tokens only.
  const LEGAL_TOKENS = [
    // Cyrillic — stripped BEFORE transliteration.
    'тоо','ип','жк','ооо','зао','оао','пао','ао','ип.','тоо.',
    // Transliterated/Turkish/EN — stripped AFTER transliteration.
    'too','llc','ltd','limited','inc','co','sh','ip','ooo','zao','oao',
    'as','anonim','şirketi','sirketi','sti','san','tic','company','corp'
  ];

  // Characters that become spaces during normalization.
  const PUNCT_RE = /["'`«»“”‘’\(\)\[\]\{\}<>,.;:!?\-_/\\|*&%#@+=]+/g;

  // ─── CORE ────────────────────────────────────────────────

  function stripLegalTokens(s) {
    // Whole-word match on token boundaries.
    const tokens = s.split(/\s+/).filter(Boolean);
    const kept = tokens.filter(t => LEGAL_TOKENS.indexOf(t) === -1);
    // If nothing remains (e.g. name WAS just "ТОО"), keep original.
    return kept.length ? kept.join(' ') : s;
  }

  function transliterateCyrillic(s) {
    let out = '';
    for (const ch of s) out += CYR_TO_LAT[ch] !== undefined ? CYR_TO_LAT[ch] : ch;
    return out;
  }

  function foldTurkish(s) {
    let out = '';
    for (const ch of s) out += TR_MAP[ch] !== undefined ? TR_MAP[ch] : ch;
    return out;
  }

  /**
   * Canonical form of a counterparty name.
   * Expected to be idempotent: normalizeName(normalizeName(x)) === normalizeName(x).
   */
  function normalizeName(name) {
    if (!name) return '';
    let s = String(name).toLowerCase().trim();

    // Strip quotes first — legal prefixes are often quoted.
    s = s.replace(PUNCT_RE, ' ');

    // Strip Cyrillic legal tokens (before transliteration).
    s = stripLegalTokens(s);

    // Transliterate.
    s = transliterateCyrillic(s);

    // Fold Turkish diacritics.
    s = foldTurkish(s);

    // Strip Latin legal tokens (after transliteration).
    s = stripLegalTokens(s);

    // Collapse whitespace.
    s = s.replace(/\s+/g, ' ').trim();

    return s;
  }

  // ─── SIMILARITY ──────────────────────────────────────────

  /** Levenshtein distance — classic DP. */
  function levenshtein(a, b) {
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    const m = a.length, n = b.length;
    // Two-row optimization.
    let prev = new Array(n + 1);
    let curr = new Array(n + 1);
    for (let j = 0; j <= n; j++) prev[j] = j;
    for (let i = 1; i <= m; i++) {
      curr[0] = i;
      for (let j = 1; j <= n; j++) {
        const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
        curr[j] = Math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
      }
      [prev, curr] = [curr, prev];
    }
    return prev[n];
  }

  function levenshteinRatio(a, b) {
    const maxLen = Math.max(a.length, b.length);
    if (!maxLen) return 1;
    return 1 - levenshtein(a, b) / maxLen;
  }

  /** Token-set Jaccard similarity. */
  function jaccard(a, b) {
    const A = new Set(a.split(/\s+/).filter(Boolean));
    const B = new Set(b.split(/\s+/).filter(Boolean));
    if (!A.size && !B.size) return 1;
    let inter = 0;
    for (const t of A) if (B.has(t)) inter++;
    const union = A.size + B.size - inter;
    return union === 0 ? 0 : inter / union;
  }

  /**
   * Blend of Levenshtein (character sequence) and Jaccard (token overlap).
   * Both inputs are normalized.
   */
  function similarity(a, b) {
    const na = normalizeName(a);
    const nb = normalizeName(b);
    if (!na || !nb) return 0;
    if (na === nb) return 1;

    // Token-sorted Levenshtein — makes ordering irrelevant ("Dina Kosker"
    // vs "Kosker Dina" converges to the same canonical form before Lev).
    // Normalization already strips legal suffixes, so "Anka Agro TOO" and
    // "Anka Agro LLC" are literally equal here.
    const sortTokens = s => s.split(/\s+/).filter(Boolean).sort().join(' ');
    const lev = levenshteinRatio(sortTokens(na), sortTokens(nb));
    const jac = jaccard(na, nb);
    // 80/20 — for company names, character-level similarity dominates
    // token overlap (one-letter typos in a single-token name should still
    // score high). Jaccard mainly helps when extra legal-suffix words slip
    // past normalization.
    return lev * 0.8 + jac * 0.2;
  }

  // ─── BEST MATCH ─────────────────────────────────────────

  /**
   * Find the highest-scoring contact for a target.
   * target: { name, bin? } — BIN bonus applied if candidate has matching tax_number.
   * candidates: [{ id, name, tax_number }]
   */
  function findBestMatch(target, candidates) {
    if (!target?.name || !candidates?.length) return null;
    let best = null;
    for (const c of candidates) {
      if (!c?.name) continue;
      let score = similarity(target.name, c.name);
      // BIN is an extra signal — add a small bonus without dominating.
      if (target.bin && c.tax_number && c.tax_number === target.bin) score = Math.min(1, score + 0.15);
      if (!best || score > best.score) best = { contact: c, score };
    }
    return best;
  }

  return {
    normalizeName,
    similarity,
    findBestMatch,
    // Exported for tests / debugging:
    _levenshtein: levenshtein,
    _jaccard: jaccard,
    _transliterateCyrillic: transliterateCyrillic
  };
});
