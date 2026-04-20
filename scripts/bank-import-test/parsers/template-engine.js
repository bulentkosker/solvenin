/**
 * Universal Import Template Engine
 * Template JSON + raw extracted data → ParsedResult
 *
 * Supports: PDF (text items with x,y positions), Excel (rows + cellMap)
 */

// ─── HELPERS ────────────────────────────────────────────

/** Sayı parse — locale-aware (thousand sep temizle, decimal normalize) */
function parseNumber(str, locale) {
  if (str == null) return 0;
  let s = String(str).trim();
  if (!s) return 0;
  const tsep = locale?.thousand_separator || ' ';
  const dsep = locale?.decimal_separator || ',';
  // Thousand separator'ı kaldır (birden fazla karakter olabilir — boşluk, nokta, virgül)
  if (tsep === ' ' || tsep === '\u00a0') s = s.replace(/[\s\u00a0]/g, '');
  else s = s.split(tsep).join('');
  // Decimal separator'ı '.' yap
  if (dsep !== '.') s = s.replace(dsep, '.');
  // Negatif işareti veya parantez: (123.45) → -123.45
  if (s.startsWith('(') && s.endsWith(')')) s = '-' + s.slice(1, -1);
  const n = parseFloat(s);
  return isNaN(n) ? 0 : n;
}

/** Tarih parse — format string: DD.MM.YYYY, DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD */
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
  } else if (fmt === 'DD-MM-YYYY') {
    const parts = s.split('-');
    if (parts.length < 3) return null;
    d = parseInt(parts[0]); m = parseInt(parts[1]); y = parseInt(parts[2]);
  } else {
    return null;
  }
  if (!d || !m || !y || d > 31 || m > 12) return null;
  if (y < 100) y += 2000;
  const date = new Date(y, m - 1, d);
  return isNaN(date.getTime()) ? null : date.toISOString().split('T')[0];
}

/** PDF: textItems'ları Y koordinatına göre satırlara grupla */
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
  if (currentRow.length) {
    currentRow.sort((a, b) => a.x - b.x);
    rows.push(currentRow);
  }
  return rows;
}

/** PDF: belirli x aralığındaki text items'ı birleştir */
function filterByXRange(items, xMin, xMax) {
  return items
    .filter(ti => ti.x >= xMin && ti.x <= xMax)
    .sort((a, b) => a.x - b.x)
    .map(ti => ti.text)
    .join(' ')
    .trim();
}

/** Regex ile text'ten veri çıkar */
function matchRegex(text, pattern, group = 1) {
  if (!text || !pattern) return null;
  const re = new RegExp(pattern, 'i');
  const m = text.match(re);
  return m ? (m[group] || m[0] || '').trim() : null;
}

/** Row'dan (textItem array veya string) düz text çıkar */
function rowToText(row) {
  if (typeof row === 'string') return row;
  if (Array.isArray(row)) return row.map(ti => typeof ti === 'string' ? ti : ti.text).join(' ').trim();
  return '';
}

// ─── PDF PARSER ─────────────────────────────────────────

function parsePdf(rawData, template) {
  const { pages } = rawData;
  const locale = template.locale || {};
  const fields = template.fields || {};
  const meta = template.metadata || {};
  const warnings = [];
  const transactions = [];

  // Metadata — tüm sayfa text'lerini birleştir
  const allText = pages.map(p => p.text).join('\n');
  const metadata = extractMetadata(allText, meta, locale);

  // Her sayfadaki textItems'ı Y-grupla
  const tolerance = template.row_detection?.y_tolerance || 2;
  const datePattern = template.row_detection?.pattern || '^\\d{2}\\.\\d{2}\\.\\d{4}';
  const dateRe = new RegExp(datePattern);

  let lineNum = 0;

  for (const page of pages) {
    const yRows = groupByY(page.textItems, tolerance);

    // Transaction satırlarını bul — tarih pattern'iyle başlayan
    let pendingTx = null;
    let continuationRows = [];

    for (const yRow of yRows) {
      const firstText = yRow[0]?.text?.trim() || '';
      const rowText = rowToText(yRow);

      if (dateRe.test(firstText)) {
        // Önceki pending tx'i bitir
        if (pendingTx) {
          transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
        }
        lineNum++;
        pendingTx = { lineNum, items: yRow, text: rowText };
        continuationRows = [];
      } else if (pendingTx) {
        // Devam satırı — karşı taraf detayları çok satırlı olabilir
        continuationRows.push({ items: yRow, text: rowText });
      }
    }
    // Son pending tx
    if (pendingTx) {
      transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
    }
  }

  if (!transactions.length) warnings.push('Hiç transaction parse edilemedi');

  return { metadata, transactions, warnings };
}

/** Tek bir PDF transaction'ını finalize et — field'ları çıkar */
function finalizePdfTx(tx, continuationRows, fields, locale, warnings) {
  // Ana satır + devam satırlarını birleştir
  const allItems = [...tx.items];
  const allText = [tx.text, ...continuationRows.map(r => r.text)].join('\n');
  continuationRows.forEach(r => allItems.push(...r.items));

  const result = { line_number: tx.lineNum };

  for (const [fieldName, rule] of Object.entries(fields)) {
    try {
      result[fieldName] = extractField(tx.items, allItems, allText, rule, locale);
    } catch (e) {
      result[fieldName] = null;
      warnings.push(`Satır ${tx.lineNum}: ${fieldName} parse hatası — ${e.message}`);
    }
  }

  // Sayıları normalize et
  if (result.debit != null) result.debit = parseNumber(result.debit, locale);
  if (result.credit != null) result.credit = parseNumber(result.credit, locale);

  // Tarih normalize et
  if (result.transaction_date && typeof result.transaction_date === 'string' && !result.transaction_date.includes('-')) {
    result.transaction_date = parseDate(result.transaction_date, locale.date_format);
  }

  return result;
}

/** Tek bir field'ı rule'a göre çıkar */
function extractField(mainRowItems, allItems, allText, rule, locale) {
  if (!rule) return null;

  switch (rule.method) {
    case 'x_coordinate_range': {
      const items = (rule.use_all_rows ? allItems : mainRowItems);
      return filterByXRange(items, rule.x_min, rule.x_max) || null;
    }
    case 'regex': {
      const text = rule.source === 'main_row' ? rowToText(mainRowItems) : allText;
      return matchRegex(text, rule.pattern, rule.group || 1);
    }
    case 'regex_in_field': {
      // allText içinden regex — multi-line block'lar için
      return matchRegex(allText, rule.pattern, rule.group || 1);
    }
    case 'x_range_then_regex': {
      const items = rule.use_all_rows ? allItems : mainRowItems;
      const text = filterByXRange(items, rule.x_min, rule.x_max);
      return matchRegex(text, rule.pattern, rule.group || 1);
    }
    default:
      return null;
  }
}

// ─── EXCEL PARSER ───────────────────────────────────────

function parseExcel(rawData, template) {
  const locale = template.locale || {};
  const sections = template.sections || [];
  const meta = template.metadata || {};
  const warnings = [];
  const transactions = [];

  // Metadata — ilk sheet'ten veya tüm sheet'lerden
  const metadata = extractExcelMetadata(rawData, meta, locale);

  let lineNum = 0;
  const sheetPattern = template.sheet_pattern ? new RegExp(template.sheet_pattern) : null;

  for (const sheet of rawData.sheets) {
    if (sheetPattern && !sheetPattern.test(sheet.sheetName)) continue;

    // Sheet adından tarih çıkarma
    let sheetDate = null;
    if (template.sheet_date_format) {
      sheetDate = parseDate(sheet.sheetName, template.sheet_date_format);
    }

    for (const section of sections) {
      // Section sheet pattern kontrolü
      if (section.sheet_pattern) {
        const sp = new RegExp(section.sheet_pattern);
        if (!sp.test(sheet.sheetName)) continue;
      }

      const cols = section.columns || {};
      const startRow = (section.start_row || 1) - 1; // 0-indexed
      const rows = sheet.rows;

      for (let ri = startRow; ri < rows.length; ri++) {
        const row = rows[ri];

        // End detection
        if (section.end_detection === 'first_empty_in_col_B') {
          const bIdx = colToIndex(cols.number || 'B');
          const cIdx = colToIndex(cols.description || 'C');
          const dIdx = colToIndex(cols.debit || 'D');
          const eIdx = colToIndex(cols.credit || 'E');
          const numVal = row[bIdx];
          const descVal = row[cIdx];
          const debVal = row[dIdx];
          const creVal = row[eIdx];
          // Sıra numarası yoksa veya "TOPLAM" benzeri ise dur
          if (numVal == null || numVal === '' || /toplam|итого|total/i.test(String(descVal))) break;
          // Sayı değilse (başlık satırı olabilir) atla
          if (isNaN(parseInt(numVal))) continue;
        }

        // Değerleri oku
        const debitVal = row[colToIndex(cols.debit || 'D')];
        const creditVal = row[colToIndex(cols.credit || 'E')];
        const descVal = row[colToIndex(cols.description || 'C')];

        // Boş satır atla
        if (!debitVal && !creditVal && !descVal) continue;

        lineNum++;
        const tx = {
          line_number: lineNum,
          section: section.name,
          transaction_date: sheetDate,
          description: descVal != null ? String(descVal).trim() : null,
          debit: parseNumber(debitVal, locale),
          credit: parseNumber(creditVal, locale),
        };

        // Ek alanlar
        if (cols.counterparty_name) {
          tx.counterparty_name = row[colToIndex(cols.counterparty_name)] || null;
        }
        if (cols.document_number) {
          tx.document_number = row[colToIndex(cols.document_number)] || null;
        }
        if (cols.number) {
          tx.document_number = tx.document_number || String(row[colToIndex(cols.number)] || '');
        }

        // Sıfır satır atla
        if (tx.debit === 0 && tx.credit === 0) continue;

        transactions.push(tx);
      }
    }
  }

  if (!transactions.length) warnings.push('Hiç transaction parse edilemedi');

  return { metadata, transactions, warnings };
}

/** Excel kolon harfini 0-indexed sayıya çevir: A→0, B→1, K→10 */
function colToIndex(col) {
  if (typeof col === 'number') return col;
  const c = String(col).toUpperCase();
  let idx = 0;
  for (let i = 0; i < c.length; i++) {
    idx = idx * 26 + (c.charCodeAt(i) - 64);
  }
  return idx - 1;
}

// ─── METADATA EXTRACTION ────────────────────────────────

function extractMetadata(allText, metaConfig, locale) {
  const result = {};
  for (const [key, rule] of Object.entries(metaConfig)) {
    if (rule.method === 'regex') {
      const raw = matchRegex(allText, rule.pattern, rule.group || 1);
      if (key.includes('balance') || key.includes('total')) {
        result[key] = raw ? parseNumber(raw, locale) : null;
      } else if (key.includes('date') || key.includes('period')) {
        result[key] = raw ? parseDate(raw, rule.date_format || locale.date_format) : raw;
      } else {
        result[key] = raw;
      }
    }
  }
  return result;
}

function extractExcelMetadata(rawData, metaConfig, locale) {
  const result = {};
  for (const [key, rule] of Object.entries(metaConfig)) {
    if (rule.method === 'cell') {
      // Belirli hücre değeri: {method: "cell", sheet: 0, cell: "D5"}
      const sheetIdx = rule.sheet || 0;
      const sheet = rawData.sheets[sheetIdx];
      if (sheet) {
        const val = sheet.cellMap[rule.cell];
        if (key.includes('balance') || key.includes('total')) {
          result[key] = val != null ? parseNumber(val, locale) : null;
        } else {
          result[key] = val != null ? val : null;
        }
      }
    } else if (rule.method === 'cell_all_sheets') {
      // Tüm sheet'lerdeki aynı hücreyi topla
      let total = 0;
      for (const sheet of rawData.sheets) {
        const val = sheet.cellMap[rule.cell];
        if (val != null) total += parseNumber(val, locale);
      }
      result[key] = total;
    }
  }
  return result;
}

// ─── MAIN ENTRY POINT ───────────────────────────────────

function parseWithTemplate(rawData, template) {
  if (template.file_format === 'pdf') {
    return parsePdf(rawData, template);
  } else if (['xlsx', 'xls', 'csv'].includes(template.file_format)) {
    return parseExcel(rawData, template);
  } else {
    return { metadata: {}, transactions: [], warnings: [`Desteklenmeyen format: ${template.file_format}`] };
  }
}

module.exports = { parseWithTemplate, parseNumber, parseDate, groupByY, filterByXRange, matchRegex };
