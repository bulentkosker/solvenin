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
  // Tüm whitespace türlerini temizle (regular space, NBSP, thin space)
  s = s.replace(/[\s\u00a0\u2009\u202f]+/g, '');
  // Thousand separator'ı kaldır (virgül veya nokta)
  if (tsep && tsep !== ' ' && tsep !== dsep) s = s.split(tsep).join('');
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
  // Timezone-safe: doğrudan YYYY-MM-DD string oluştur, Date objesine çevirme
  return `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
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

  // Metadata — tüm sayfa text'lerini birleştir + whitespace normalize (multi-line regex fix)
  const allText = pages.map(p => p.text).join('\n');
  const normalizedText = allText.replace(/\s+/g, ' ');
  const metadata = extractMetadata(normalizedText, meta, locale);

  // Her sayfadaki textItems'ı Y-grupla
  const tolerance = template.row_detection?.y_tolerance || 2;
  const datePattern = template.row_detection?.pattern || '^\\d{2}\\.\\d{2}\\.\\d{4}';
  const dateRe = new RegExp(datePattern);

  const skipHeaderY = template.row_detection?.skip_header_y || 0;
  const stopRe = template.row_detection?.stop_pattern ? new RegExp(template.row_detection.stop_pattern, 'i') : null;
  let lineNum = 0;

  for (const page of pages) {
    const yRows = groupByY(page.textItems, tolerance);

    // Transaction satırlarını bul — tarih pattern'iyle başlayan
    let pendingTx = null;
    let continuationRows = [];

    for (const yRow of yRows) {
      // İlk sayfada header bölgesini atla
      if (skipHeaderY && page.pageNumber === 1 && yRow[0]?.y < skipHeaderY) continue;
      const firstText = yRow[0]?.text?.trim() || '';
      const rowText = rowToText(yRow);
      // Tarih pattern: ilk non-empty item'da veya belirli x aralığındaki item'da ara
      const dateItems = template.row_detection?.date_x_min != null
        ? yRow.filter(ti => ti.x >= template.row_detection.date_x_min && ti.x <= (template.row_detection.date_x_max || 120))
        : [yRow.find(ti => ti.text?.trim()) || yRow[0]];
      const hasDateMatch = dateItems.some(ti => dateRe.test(ti?.text?.trim()));

      if (hasDateMatch) {
        // Önceki pending tx'i bitir
        if (pendingTx) {
          transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
        }
        lineNum++;
        pendingTx = { lineNum, items: yRow, text: rowText };
        continuationRows = [];
      } else if (pendingTx) {
        // Stop pattern: totals/summary satırına ulaşınca tx'i bitir, devam etme
        if (stopRe && stopRe.test(rowText)) {
          transactions.push(finalizePdfTx(pendingTx, continuationRows, fields, locale, warnings));
          pendingTx = null;
          continuationRows = [];
          continue;
        }
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

        // End detection — always check, default to empty-col-number + TOPLAMLAR
        {
          const bIdx = colToIndex(cols.number || 'B');
          const cIdx = colToIndex(cols.description || 'C');
          const dIdx = colToIndex(cols.debit || 'D');
          const eIdx = colToIndex(cols.credit || 'E');
          const numVal = row[bIdx];
          const descVal = row[cIdx];
          const debVal = row[dIdx];
          const creVal = row[eIdx];
          // Sıra numarası yoksa veya "TOPLAM" benzeri ise dur
          const descNorm = String(descVal || '').replace(/\s/g, '');
          if (numVal == null || numVal === '' || /toplam|итого|total|toplamlar/i.test(descNorm)) break;
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
        const cleanRaw = raw ? raw.replace(/\s/g, '') : raw;
        result[key] = cleanRaw ? parseDate(cleanRaw, rule.date_format || locale.date_format) : raw;
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

// ─── AUTO-CALIBRATION (PDF only) ────────────────────────

/** Tüm sayısal text items'ı bul (locale-aware) */
function findNumericItems(pages, locale) {
  const dsep = locale?.decimal_separator || ',';
  // Match numbers like: 128 591,10 or 32,291.25 or 5180000
  const numRe = dsep === ',' ? /^[\d\s]+,\d{1,2}$/ : /^[\d,]+\.\d{1,2}$/;
  const items = [];
  for (const page of pages) {
    for (const ti of page.textItems) {
      const t = ti.text.trim().replace(/[\s\u00a0]/g, '');
      if (numRe.test(ti.text.trim()) || /^\d[\d\s,.]{2,}\d$/.test(ti.text.trim())) {
        const val = parseNumber(ti.text, locale);
        if (val > 0) items.push({ ...ti, numericValue: val });
      }
    }
  }
  return items;
}

/** Balance check: opening + credit - debit ≈ closing */
function checkBalance(metadata, transactions) {
  const opening = metadata?.opening_balance;
  const closing = metadata?.closing_balance;
  if (opening == null || closing == null) return { ok: null, reason: 'missing_metadata' };

  const totalDebit = transactions.reduce((s, t) => s + (t.debit || 0), 0);
  const totalCredit = transactions.reduce((s, t) => s + (t.credit || 0), 0);
  const expected = closing;
  const actual = opening + totalCredit - totalDebit;
  const tolerance = Math.max(0.02, Math.abs(opening) * 0.0001);
  const ok = Math.abs(actual - expected) <= tolerance;
  return { ok, expected, actual, diff: actual - expected, totalDebit, totalCredit };
}

/** Auto-calibrate x ranges based on actual numeric item positions */
function autoCalibrateRanges(transactions, template, rawData) {
  const locale = template.locale || {};
  const fields = template.fields || {};
  const changes = [];
  let changed = false;

  // Deep clone template
  const cal = JSON.parse(JSON.stringify(template));

  // Find all numeric items in raw data
  const numItems = findNumericItems(rawData.pages, locale);
  if (!numItems.length) return { template: cal, changed: false, changes };

  // Collect actual x positions of parsed debit/credit values
  const debitXs = [], creditXs = [];
  const tolerance = cal.row_detection?.y_tolerance || 3;

  // Find which numeric items actually correspond to transactions
  for (const tx of transactions) {
    if (!tx._items) continue; // Need raw items info
  }

  // Strategy: look at numeric items in transaction Y zones
  // and see which x ranges have values
  const txYZones = []; // y ranges where transactions were detected
  const datePattern = cal.row_detection?.pattern || '^\\d{2}\\.\\d{2}\\.\\d{4}';
  const dateRe = new RegExp(datePattern);

  for (const page of rawData.pages) {
    const yRows = groupByY(page.textItems, tolerance);
    for (const row of yRows) {
      const dateItems = cal.row_detection?.date_x_min != null
        ? row.filter(ti => ti.x >= cal.row_detection.date_x_min && ti.x <= (cal.row_detection.date_x_max || 120))
        : [row.find(ti => ti.text?.trim()) || row[0]];
      if (dateItems.some(ti => dateRe.test(ti?.text?.trim()))) {
        const yMin = Math.min(...row.map(r => r.y));
        const yMax = Math.max(...row.map(r => r.y));
        txYZones.push({ yMin: yMin - 2, yMax: yMax + 20 }); // Include continuation rows
      }
    }
  }

  // Find numeric items within transaction zones
  for (const ni of numItems) {
    const inZone = txYZones.some(z => ni.y >= z.yMin && ni.y <= z.yMax);
    if (!inZone) continue;

    const debitRule = fields.debit;
    const creditRule = fields.credit;
    if (!debitRule || !creditRule) continue;

    const inDebit = ni.x >= debitRule.x_min && ni.x <= debitRule.x_max;
    const inCredit = ni.x >= creditRule.x_min && ni.x <= creditRule.x_max;

    if (inDebit) debitXs.push(ni.x);
    else if (inCredit) creditXs.push(ni.x);
    else {
      // Numeric item not in either range — potential miss
      // Assign to closer one
      const distToDebit = Math.min(Math.abs(ni.x - debitRule.x_min), Math.abs(ni.x - debitRule.x_max));
      const distToCredit = Math.min(Math.abs(ni.x - creditRule.x_min), Math.abs(ni.x - creditRule.x_max));
      if (distToDebit < distToCredit && distToDebit < 30) debitXs.push(ni.x);
      else if (distToCredit < 30) creditXs.push(ni.x);
    }
  }

  // Simple calibration: check if any transactions have both debit AND credit > 0
  // (overlap indicator) or if many transactions have both = 0 (range too narrow)
  const bothNonZero = transactions.filter(tx => (tx.debit || 0) > 0 && (tx.credit || 0) > 0).length;
  const bothZero = transactions.filter(tx => (tx.debit || 0) === 0 && (tx.credit || 0) === 0).length;

  if (fields.debit?.method === 'x_coordinate_range' && fields.credit?.method === 'x_coordinate_range') {
    const dRule = cal.fields.debit, cRule = cal.fields.credit;

    // Fix overlap: debit x_max >= credit x_min
    if (dRule.x_max >= cRule.x_min) {
      const mid = Math.round((dRule.x_max + cRule.x_min) / 2);
      const oldD = [dRule.x_min, dRule.x_max], oldC = [cRule.x_min, cRule.x_max];
      dRule.x_max = mid - 2;
      cRule.x_min = mid + 2;
      changes.push({ field: 'debit_credit_split', old_debit: oldD, old_credit: oldC, new_debit: [dRule.x_min, dRule.x_max], new_credit: [cRule.x_min, cRule.x_max], reason: 'overlap' });
      changed = true;
    }

    // If too many both-zero → widen ranges by 15px each
    if (bothZero > transactions.length * 0.3) {
      dRule.x_min -= 15; dRule.x_max += 15;
      cRule.x_min -= 15; cRule.x_max += 15;
      // Re-fix overlap
      if (dRule.x_max >= cRule.x_min) {
        const mid = Math.round((dRule.x_max + cRule.x_min) / 2);
        dRule.x_max = mid - 2; cRule.x_min = mid + 2;
      }
      changes.push({ field: 'both_widened', reason: `${bothZero}/${transactions.length} transactions had both=0` });
      changed = true;
    }
  }

  return { template: cal, changed, changes };
}

/** Widen all x ranges by given pixels */
function widenRanges(template, px) {
  const t = JSON.parse(JSON.stringify(template));
  if (!t.fields) return t;
  for (const [key, rule] of Object.entries(t.fields)) {
    if (rule?.method === 'x_coordinate_range') {
      rule.x_min = (rule.x_min || 0) - px;
      rule.x_max = (rule.x_max || 0) + px;
    }
  }
  return t;
}

// ─── MAIN ENTRY POINT ───────────────────────────────────

function parseWithTemplate(rawData, template) {
  if (template.file_format === 'pdf') {
    return parsePdfWithCalibration(rawData, template);
  } else if (['xlsx', 'xls', 'csv'].includes(template.file_format)) {
    return parseExcel(rawData, template);
  } else {
    return { metadata: {}, transactions: [], warnings: [`Desteklenmeyen format: ${template.file_format}`] };
  }
}

/** PDF parse with auto-calibration loop */
function parsePdfWithCalibration(rawData, template) {
  // First pass
  let result = parsePdf(rawData, template);
  let calibration_info = { auto_calibrated: false, iterations: 1, changes: [], balance_check: null };

  // Balance check
  let balCheck = checkBalance(result.metadata, result.transactions);
  calibration_info.balance_check = balCheck;

  if (balCheck.ok === true) {
    // Perfect — no calibration needed
    result.calibration_info = calibration_info;
    return result;
  }

  // Try auto-calibration
  const calResult = autoCalibrateRanges(result.transactions, template, rawData);
  if (calResult.changed) {
    calibration_info.auto_calibrated = true;
    calibration_info.changes = calResult.changes;
    calibration_info.iterations = 2;

    // Re-parse with calibrated template
    result = parsePdf(rawData, calResult.template);
    balCheck = checkBalance(result.metadata, result.transactions);
    calibration_info.balance_check = balCheck;

    if (balCheck.ok === true) {
      result.calibration_info = calibration_info;
      return result;
    }

    // Third attempt — widen ranges
    const wider = widenRanges(calResult.template, 10);
    const result3 = parsePdf(rawData, wider);
    const balCheck3 = checkBalance(result3.metadata, result3.transactions);

    if (balCheck3.ok === true || (balCheck3.diff != null && Math.abs(balCheck3.diff) < Math.abs(balCheck.diff))) {
      calibration_info.iterations = 3;
      calibration_info.balance_check = balCheck3;
      result3.calibration_info = calibration_info;
      return result3;
    }
  }

  // Return best result
  result.calibration_info = calibration_info;
  return result;
}

module.exports = { parseWithTemplate, parseNumber, parseDate, groupByY, filterByXRange, matchRegex };
