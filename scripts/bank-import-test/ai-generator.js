/**
 * AI Template Generator
 * Bilinmeyen formatta ekstre yüklendiğinde Claude API ile template JSON üretir.
 */
const fs = require('fs');
const path = require('path');

// ─── COMPRESS RAW DATA ──────────────────────────────────

function compressPdfExtract(rawData, maxPages = 2) {
  return {
    pages: rawData.pages.slice(0, maxPages).map(p => ({
      pageNumber: p.pageNumber,
      width: p.width,
      height: p.height,
      text: p.text.slice(0, 2000),
      textItems: p.textItems.slice(0, 150).map(ti => ({
        text: ti.text,
        x: Math.round(ti.x * 10) / 10,
        y: Math.round(ti.y * 10) / 10,
        w: Math.round(ti.width * 10) / 10,
      })),
    })),
    metadata: rawData.metadata,
  };
}

function compressExcelExtract(rawData, maxSheets = 3, maxRows = 30) {
  return {
    sheets: rawData.sheets.slice(0, maxSheets).map(s => ({
      sheetName: s.sheetName,
      totalRows: s.totalRows,
      totalCols: s.totalCols,
      rows: s.rows.slice(0, maxRows),
      merges: s.merges.slice(0, 10),
    })),
    fileName: rawData.fileName,
    sheetCount: rawData.sheetCount,
  };
}

// ─── FEW-SHOT EXAMPLES ─────────────────────────────────

function loadFewShotExamples() {
  const tDir = path.join(__dirname, 'templates');
  const sDir = path.join(__dirname, 'samples');
  const examples = [];

  const pairs = [
    { template: 'halyk-kz-pdf.json', output: 'output-halyk.txt', label: 'Halyk Bank KZ PDF' },
    { template: 'bcc-kz-pdf.json', output: 'output-bcc.txt', label: 'BCC Bank KZ PDF (landscape)' },
    { template: 'generic-cashbook.json', output: 'output-cashbook.txt', label: 'Cash/Bank Ledger Excel' },
  ];

  for (const pair of pairs) {
    try {
      const template = JSON.parse(fs.readFileSync(path.join(tDir, pair.template), 'utf8'));
      const outputPath = path.join(sDir, pair.output);
      let rawSample = '';
      if (fs.existsSync(outputPath)) {
        rawSample = fs.readFileSync(outputPath, 'utf8').slice(0, 1200);
      }
      examples.push({ label: pair.label, rawSample, template });
    } catch (e) {
      // Skip missing examples
    }
  }
  return examples;
}

// ─── SYSTEM PROMPT ──────────────────────────────────────

const SYSTEM_PROMPT = `Sen bir banka ekstresi / kasa defteri parser template üreticisisin.

Kullanıcı sana bir finansal dosyanın ham extract çıktısını gönderecek. Senin görevin bu dosyayı parse edebilecek bir template JSON üretmek.

## Template JSON Schema

{
  "name": "Template adı (banka adı + format)",
  "file_format": "pdf" | "xlsx",
  "country_code": "KZ" | "TR" | "US" | ...,
  "language_code": "ru" | "tr" | "en" | ...,
  "bank_name": "Banka adı (null if not a bank statement)",
  "bank_identifier": "SWIFT/BIC kodu (varsa)",

  "locale": {
    "decimal_separator": "." veya ",",
    "thousand_separator": " " veya "," veya "." (decimal_separator'dan farklı olmalı!),
    "date_format": "DD.MM.YYYY" | "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD"
  },

  "row_detection": {          // Sadece PDF için
    "method": "y_coordinate_grouping",
    "pattern": "regex — her transaction satırı bu pattern'le tanınır (genelde tarih)",
    "y_tolerance": 2-6,        // Aynı Y (±tolerans) = aynı satır
    "skip_header_y": number,   // İlk sayfada bu Y'den öncekileri atla (header bölgesi)
    "date_x_min": number,      // Tarih item'ının beklenen x aralığı (header tarihlerini filtrelemek için)
    "date_x_max": number,
    "stop_pattern": "regex — bu pattern'e uyan satırda transaction'ları durdur (ör: Итого|Total)"
  },

  "sections": [               // Sadece Excel için — bir sheet'te birden fazla tablo
    {
      "name": "cash" | "bank" | ...,
      "sheet_pattern": "regex — hangi sheet'lerde",
      "start_row": number,     // 1-indexed, data başlangıcı (header'lar atlanır)
      "end_detection": "first_empty_in_col_B",
      "columns": {
        "number": "B", "description": "C", "debit": "D", "credit": "E"
      }
    }
  ],

  "sheet_date_format": "DD.MM.YYYY",  // Excel: sheet adından tarih çıkarma formatı

  "fields": {                 // Her transaction'dan çıkarılacak alanlar
    "transaction_date": {
      "method": "x_coordinate_range" | "regex" | "regex_in_field",
      "x_min": number, "x_max": number,        // PDF x-range
      "use_all_rows": true | false,             // continuation satırları da dahil et
      "pattern": "regex pattern",
      "group": 1                                // regex group numarası
    },
    "document_number": { ... },
    "debit": { ... },
    "credit": { ... },
    "counterparty_name": { ... },
    "counterparty_bin": {
      "method": "regex_in_field",
      "pattern": "BIN/IIN regex — ör: БИН\\\\s*(\\\\d{12})"
    },
    "payment_details": { ... },
    "knp_code": { ... },
    "external_reference": { ... }
  },

  "metadata": {               // Dosya geneli bilgiler
    "account_iban": { "method": "regex", "pattern": "IBAN regex" },
    "opening_balance": { "method": "regex", "pattern": "..." },
    "closing_balance": { "method": "regex", "pattern": "..." },
    "period_start": { "method": "regex", "pattern": "...", "date_format": "DD-MM-YYYY" },
    "period_end": { "method": "regex", "pattern": "...", "date_format": "DD-MM-YYYY" }
  }
}

## PDF Template Kuralları

1. textItems x,y koordinatlarını analiz et:
   - Aynı y (±tolerance) = aynı satır
   - X kümeleri = tablo kolonları (tarih, belge no, debit, credit, karşı taraf...)
   - Header/metadata bölgesi genelde y < 250-300

2. Transaction başlangıcını tespit et:
   - Genelde tarih pattern'i ile (DD.MM.YYYY)
   - date_x_min/date_x_max ile header tarihlerini filtrele

3. Çok satırlı alanlar (counterparty, payment details):
   - use_all_rows: true → continuation satırları da dahil eder

4. Sayı formatını locale'den belirle:
   - "128 591,10" → thousand=" ", decimal=","
   - "32,291.25" → thousand=",", decimal="."

## Excel Template Kuralları

1. Sheet yapısını analiz et (rows, merges)
2. Sections ile yanyana tablolar tanımla (ör: kasa sol, banka sağ)
3. sheet_date_format ile sheet adından tarih çıkar
4. start_row ile header satırlarını atla
5. end_detection ile data sonu tespit et

## Zorunlu Alanlar
- transaction_date, debit, credit (en az biri > 0 olmalı)
- counterparty_name (varsa)

## ÖNEMLİ
- locale.decimal_separator ≠ locale.thousand_separator
- Çıktı YALNIZCA valid JSON. Açıklama, markdown, code fence YAZMA.
- Regex'lerde backslash'ları JSON escape et (\\\\d değil \\d yaz — JSON string'de \\ gerekli)`;

// ─── CLAUDE API CALL ────────────────────────────────────

async function callClaude(messages, apiKey, maxRetries = 2) {
  let lastError = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const body = {
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages,
    };

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
    });

    const data = await res.json();

    if (data.error) {
      lastError = data.error.message || JSON.stringify(data.error);
      console.error(`API error (attempt ${attempt + 1}):`, lastError);
      continue;
    }

    const text = (data.content || []).map(b => b.text || '').join('');
    const usage = data.usage || {};

    // JSON parse
    try {
      // Clean: remove code fences if present
      let jsonStr = text.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
      }
      const template = JSON.parse(jsonStr);
      return { template, tokens_used: usage, raw_response: text, attempts: attempt + 1 };
    } catch (parseErr) {
      lastError = `JSON parse error: ${parseErr.message}`;
      console.error(`JSON parse failed (attempt ${attempt + 1}):`, parseErr.message);
      // Retry with hint
      if (attempt < maxRetries) {
        messages = [
          ...messages,
          { role: 'assistant', content: text },
          { role: 'user', content: 'JSON parse hatası oldu. SADECE geçerli JSON döndür, başka hiçbir şey yazma. Code fence (```) kullanma.' },
        ];
      }
    }
  }

  throw new Error(`AI template generation failed after ${maxRetries + 1} attempts: ${lastError}`);
}

// ─── TEMPLATE VALIDATOR ─────────────────────────────────

function validateTemplate(template) {
  const errors = [];
  const warnings = [];

  if (!template.name) errors.push('name eksik');
  if (!template.file_format) errors.push('file_format eksik');
  if (!['pdf', 'xlsx', 'xls', 'csv', 'txt'].includes(template.file_format)) errors.push('file_format geçersiz: ' + template.file_format);

  // Locale
  if (!template.locale) errors.push('locale eksik');
  else {
    if (!template.locale.decimal_separator) warnings.push('locale.decimal_separator eksik');
    if (template.locale.decimal_separator === template.locale.thousand_separator) {
      errors.push('decimal_separator ve thousand_separator aynı olamaz: ' + template.locale.decimal_separator);
    }
    if (!template.locale.date_format) warnings.push('locale.date_format eksik');
  }

  // Fields
  if (!template.fields) errors.push('fields eksik');
  else {
    if (!template.fields.transaction_date) warnings.push('fields.transaction_date eksik');
    if (!template.fields.debit && !template.fields.credit) errors.push('fields.debit veya fields.credit en az biri olmalı');
  }

  // PDF specifics
  if (template.file_format === 'pdf' && !template.row_detection) {
    warnings.push('PDF template için row_detection önerilir');
  }

  // Excel specifics
  if (['xlsx', 'xls'].includes(template.file_format) && (!template.sections || !template.sections.length)) {
    warnings.push('Excel template için sections önerilir');
  }

  return { valid: errors.length === 0, errors, warnings };
}

// ─── MAIN GENERATOR ─────────────────────────────────────

async function generateTemplate(rawExtract, fileInfo, anthropicApiKey) {
  // 1. Compress
  const compressed = fileInfo.format === 'pdf'
    ? compressPdfExtract(rawExtract)
    : compressExcelExtract(rawExtract);

  // 2. Few-shot examples
  const examples = loadFewShotExamples();
  let fewShotText = '';
  for (const ex of examples) {
    fewShotText += `\n--- ÖRNEK: ${ex.label} ---\nRAW EXTRACT (ilk kısım):\n${ex.rawSample}\n\nÜRETİLEN TEMPLATE:\n${JSON.stringify(ex.template, null, 2)}\n`;
  }

  // 3. User message
  const userMessage = `Sana şu dosyanın ham extract çıktısını gönderiyorum. Bu bir ${fileInfo.target_module === 'bank_statement' ? 'banka ekstresi' : 'kasa defteri'}.

FILE INFO:
${JSON.stringify(fileInfo, null, 2)}

RAW EXTRACT:
${JSON.stringify(compressed, null, 2)}

ÖRNEKLER (referans — bu formatlara benzer template üret):
${fewShotText}

Cevabını SADECE JSON olarak ver. Başka açıklama yazma.`;

  // 4. API call
  const messages = [{ role: 'user', content: userMessage }];
  const result = await callClaude(messages, anthropicApiKey);

  // 5. Validate
  const validation = validateTemplate(result.template);

  return {
    template: result.template,
    confidence: validation.valid ? (validation.warnings.length === 0 ? 'high' : 'medium') : 'low',
    validation,
    tokens_used: result.tokens_used,
    attempts: result.attempts,
  };
}

module.exports = { generateTemplate, validateTemplate, compressPdfExtract, compressExcelExtract };
