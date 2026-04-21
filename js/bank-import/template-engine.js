/**
 * Universal Import Template Engine — Browser version
 * Copy of scripts/bank-import-test/parsers/template-engine.js adapted for browser.
 * Exposed as window.BankImportEngine
 */
(function() {
'use strict';

function parseNumber(str, locale) {
  if (str == null) return 0;
  let s = String(str).trim();
  if (!s) return 0;
  const tsep = locale?.thousand_separator || ' ';
  const dsep = locale?.decimal_separator || ',';
  s = s.replace(/[\s\u00a0\u2009\u202f]+/g, '');
  if (tsep && tsep !== ' ' && tsep !== dsep) s = s.split(tsep).join('');
  if (dsep !== '.') s = s.replace(dsep, '.');
  if (s.startsWith('(') && s.endsWith(')')) s = '-' + s.slice(1, -1);
  const n = parseFloat(s);
  return isNaN(n) ? 0 : n;
}

function parseDate(str, format) {
  if (!str) return null;
  const s = String(str).trim();
  if (!s) return null;
  const fmt = (format || 'DD.MM.YYYY').toUpperCase();
  let d, m, y;
  if (fmt === 'DD.MM.YYYY' || fmt === 'DD/MM/YYYY' || fmt === 'DD-MM-YYYY') {
    const parts = s.split(/[.\/\-]/);
    if (parts.length < 3) return null;
    d = parseInt(parts[0]); m = parseInt(parts[1]); y = parseInt(parts[2]);
  } else if (fmt === 'YYYY-MM-DD') {
    const parts = s.split('-');
    if (parts.length < 3) return null;
    y = parseInt(parts[0]); m = parseInt(parts[1]); d = parseInt(parts[2]);
  } else { return null; }
  if (!d || !m || !y || d > 31 || m > 12) return null;
  if (y < 100) y += 2000;
  return `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
}

function groupByY(textItems, tolerance = 2) {
  if (!textItems?.length) return [];
  const sorted = [...textItems].sort((a, b) => a.y - b.y || a.x - b.x);
  const rows = [];
  let currentRow = [sorted[0]];
  let currentY = sorted[0].y;
  for (let i = 1; i < sorted.length; i++) {
    if (Math.abs(sorted[i].y - currentY) <= tolerance) {
      currentRow.push(sorted[i]);
    } else {
      currentRow.sort((a, b) => a.x - b.x);
      rows.push(currentRow);
      currentRow = [sorted[i]];
      currentY = sorted[i].y;
    }
  }
  if (currentRow.length) { currentRow.sort((a, b) => a.x - b.x); rows.push(currentRow); }
  return rows;
}

function filterByXRange(items, xMin, xMax) {
  return items.filter(ti => ti.x >= xMin && ti.x <= xMax).sort((a, b) => a.x - b.x).map(ti => ti.text).join(' ').trim();
}

function matchRegex(text, pattern, group = 1) {
  if (!text || !pattern) return null;
  const m = text.match(new RegExp(pattern, 'i'));
  return m ? (m[group] || m[0] || '').trim() : null;
}

function rowToText(row) {
  if (typeof row === 'string') return row;
  if (Array.isArray(row)) return row.map(ti => typeof ti === 'string' ? ti : ti.text).join(' ').trim();
  return '';
}

function colToIndex(col) {
  if (typeof col === 'number') return col;
  const c = String(col).toUpperCase();
  let idx = 0;
  for (let i = 0; i < c.length; i++) idx = idx * 26 + (c.charCodeAt(i) - 64);
  return idx - 1;
}

// ─── PDF PARSER ─────────────────────────────────────────

function parsePdf(rawData, template) {
  const { pages } = rawData;
  const locale = template.locale || {};
  const fields = template.fields || {};
  const meta = template.metadata || {};
  const warnings = [];
  const transactions = [];

  const allText = pages.map(p => p.text).join('\n');
  const normalizedText = allText.replace(/\s+/g, ' ');
  const metadata = extractMetadata(normalizedText, meta, locale);

  const tolerance = template.row_detection?.y_tolerance || 2;
  const datePattern = template.row_detection?.pattern || '^\\d{2}\\.\\d{2}\\.\\d{4}';
  const dateRe = new RegExp(datePattern);
  const skipHeaderY = template.row_detection?.skip_header_y || 0;
  const stopRe = template.row_detection?.stop_pattern ? new RegExp(template.row_detection.stop_pattern, 'i') : null;
  let lineNum = 0;

  for (const page of pages) {
    const yRows = groupByY(page.textItems, tolerance);
    let pendingTx = null;
    let continuationRows = [];

    for (const yRow of yRows) {
      if (skipHeaderY && page.pageNumber === 1 && yRow[0]?.y < skipHeaderY) continue;
      const rowText = rowToText(yRow);
      const dateItems = template.row_detection?.date_x_min != null
        ? yRow.filter(ti => ti.x >= template.row_detection.date_x_min && ti.x <= (template.row_detection.date_x_max || 120))
        : [yRow.find(ti => ti.text?.trim()) || yRow[0]];
      const hasDateMatch = dateItems.some(ti => dateRe.test(ti?.text?.trim()));

      if (hasDateMatch) {
        if (pendingTx) transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
        lineNum++;
        pendingTx = { lineNum, items: yRow, text: rowText };
        continuationRows = [];
      } else if (pendingTx) {
        if (stopRe && stopRe.test(rowText)) {
          transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
          pendingTx = null; continuationRows = []; continue;
        }
        continuationRows.push({ items: yRow, text: rowText });
      }
    }
    if (pendingTx) transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
  }

  if (!transactions.length) warnings.push('Hiç transaction parse edilemedi');
  return { metadata, transactions, warnings };
}

function finalizePdfTx(tx, continuationRows, fields, locale, warnings) {
  const allItems = [...tx.items];
  const allText = [tx.text, ...continuationRows.map(r => r.text)].join('\n');
  continuationRows.forEach(r => allItems.push(...r.items));
  const result = { line_number: tx.lineNum };
  for (const [fieldName, rule] of Object.entries(fields)) {
    try { result[fieldName] = extractField(tx.items, allItems, allText, rule, locale); }
    catch (e) { result[fieldName] = null; }
  }
  if (result.debit != null) result.debit = parseNumber(result.debit, locale);
  if (result.credit != null) result.credit = parseNumber(result.credit, locale);
  if (result.transaction_date && typeof result.transaction_date === 'string' && !result.transaction_date.includes('-')) {
    result.transaction_date = parseDate(result.transaction_date, locale.date_format);
  }
  return result;
}

function extractField(mainRowItems, allItems, allText, rule, locale) {
  if (!rule) return null;
  switch (rule.method) {
    case 'x_coordinate_range': {
      const items = rule.use_all_rows ? allItems : mainRowItems;
      return filterByXRange(items, rule.x_min, rule.x_max) || null;
    }
    case 'regex': {
      const text = rule.source === 'main_row' ? rowToText(mainRowItems) : allText;
      return matchRegex(text, rule.pattern, rule.group || 1);
    }
    case 'regex_in_field': return matchRegex(allText, rule.pattern, rule.group || 1);
    default: return null;
  }
}

// ─── EXCEL PARSER ───────────────────────────────────────

function parseExcel(rawData, template) {
  const locale = template.locale || {};
  const sections = template.sections || [];
  const meta = template.metadata || {};
  const warnings = [];
  const transactions = [];
  const metadata = extractExcelMetadata(rawData, meta, locale);
  let lineNum = 0;
  const sheetPattern = template.sheet_pattern ? new RegExp(template.sheet_pattern) : null;

  for (const sheet of rawData.sheets) {
    if (sheetPattern && !sheetPattern.test(sheet.sheetName)) continue;
    let sheetDate = null;
    if (template.sheet_date_format) sheetDate = parseDate(sheet.sheetName, template.sheet_date_format);

    for (const section of sections) {
      if (section.sheet_pattern && !new RegExp(section.sheet_pattern).test(sheet.sheetName)) continue;
      const cols = section.columns || {};
      const startRow = (section.start_row || 1) - 1;
      const rows = sheet.rows;

      for (let ri = startRow; ri < rows.length; ri++) {
        const row = rows[ri];
        {
          const bIdx = colToIndex(cols.number || 'B');
          const cIdx = colToIndex(cols.description || 'C');
          const numVal = row[bIdx];
          const descVal = row[cIdx];
          const descNorm = String(descVal || '').replace(/\s/g, '');
          if (numVal == null || numVal === '' || /toplam|итого|total|toplamlar/i.test(descNorm)) break;
          if (isNaN(parseInt(numVal))) continue;
        }
        const debitVal = row[colToIndex(cols.debit || 'D')];
        const creditVal = row[colToIndex(cols.credit || 'E')];
        const descVal = row[colToIndex(cols.description || 'C')];
        if (!debitVal && !creditVal && !descVal) continue;
        lineNum++;
        const tx = {
          line_number: lineNum, section: section.name, transaction_date: sheetDate,
          description: descVal != null ? String(descVal).trim() : null,
          debit: parseNumber(debitVal, locale), credit: parseNumber(creditVal, locale),
        };
        if (cols.counterparty_name) tx.counterparty_name = row[colToIndex(cols.counterparty_name)] || null;
        if (cols.number) tx.document_number = String(row[colToIndex(cols.number)] || '');
        if (tx.debit === 0 && tx.credit === 0) continue;
        transactions.push(tx);
      }
    }
  }
  if (!transactions.length) warnings.push('Hiç transaction parse edilemedi');
  return { metadata, transactions, warnings };
}

// ─── METADATA ───────────────────────────────────────────

function extractMetadata(allText, metaConfig, locale) {
  const result = {};
  for (const [key, rule] of Object.entries(metaConfig)) {
    if (rule.method === 'regex') {
      const raw = matchRegex(allText, rule.pattern, rule.group || 1);
      if (key.includes('balance') || key.includes('total')) {
        result[key] = raw ? parseNumber(raw, locale) : null;
      } else if (key.includes('date') || key.includes('period')) {
        const cleanRaw = raw ? raw.replace(/\s/g, '') : raw;
        result[key] = cleanRaw ? parseDate(cleanRaw, rule.date_format || locale.date_format) : raw;
      } else { result[key] = raw; }
    }
  }
  return result;
}

function extractExcelMetadata(rawData, metaConfig, locale) {
  const result = {};
  for (const [key, rule] of Object.entries(metaConfig)) {
    if (rule.method === 'cell') {
      const sheet = rawData.sheets[rule.sheet || 0];
      if (sheet) {
        const val = sheet.cellMap[rule.cell];
        result[key] = (key.includes('balance') || key.includes('total')) ? (val != null ? parseNumber(val, locale) : null) : (val ?? null);
      }
    }
  }
  return result;
}

// ─── BALANCE CHECK ──────────────────────────────────────

function checkBalance(metadata, transactions) {
  const opening = metadata?.opening_balance;
  const closing = metadata?.closing_balance;
  if (opening == null || closing == null) return { ok: null, reason: 'missing_metadata' };
  const totalDebit = transactions.reduce((s, t) => s + (t.debit || 0), 0);
  const totalCredit = transactions.reduce((s, t) => s + (t.credit || 0), 0);
  const actual = opening + totalCredit - totalDebit;
  const tolerance = Math.max(0.02, Math.abs(opening) * 0.0001);
  return { ok: Math.abs(actual - closing) <= tolerance, expected: closing, actual, diff: actual - closing, totalDebit, totalCredit };
}

// ─── MAIN ───────────────────────────────────────────────

function parseWithTemplate(rawData, template) {
  if (template.file_format === 'pdf') return parsePdf(rawData, template);
  if (['xlsx', 'xls', 'csv'].includes(template.file_format)) return parseExcel(rawData, template);
  return { metadata: {}, transactions: [], warnings: ['Desteklenmeyen format'] };
}

window.BankImportEngine = { parseWithTemplate, parseNumber, parseDate, checkBalance };
})();
