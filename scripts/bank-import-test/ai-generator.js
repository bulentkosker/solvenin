/**
 * AI Template Generator v2 — Chain-of-Thought + X-Coordinate Measurement
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
      text: p.text.slice(0, 2500),
      textItems: p.textItems.slice(0, 200).map(ti => ({
        text: ti.text,
        x: Math.round(ti.x * 10) / 10,
        y: Math.round(ti.y * 10) / 10,
        w: Math.round(ti.width * 10) / 10,
      })),
    })),
    metadata: rawData.metadata,
  };
}

function compressExcelExtract(rawData, maxSheets = 3, maxRows = 25) {
  return {
    sheets: rawData.sheets.slice(0, maxSheets).map(s => ({
      sheetName: s.sheetName,
      totalRows: s.totalRows,
      totalCols: s.totalCols,
      rows: s.rows.slice(0, maxRows),
      merges: s.merges.slice(0, 15),
      // Cell map for first sheet — helps AI see dual-section layout
      cellMap: Object.fromEntries(
        Object.entries(s.cellMap).filter(([addr]) => {
          const row = parseInt(addr.replace(/[A-Z]/g, ''));
          return row <= maxRows;
        }).slice(0, 80)
      ),
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
    { template: 'halyk-kz-pdf.json', output: 'output-halyk.txt', label: 'Halyk Bank KZ PDF (portrait)' },
    { template: 'bcc-kz-pdf.json', output: 'output-bcc.txt', label: 'BCC Bank KZ PDF (landscape)' },
    { template: 'generic-cashbook.json', output: 'output-cashbook.txt', label: 'Cash/Bank Ledger Excel (dual-section)' },
  ];

  for (const pair of pairs) {
    try {
      const template = JSON.parse(fs.readFileSync(path.join(tDir, pair.template), 'utf8'));
      const outputPath = path.join(sDir, pair.output);
      let rawSample = '';
      if (fs.existsSync(outputPath)) {
        rawSample = fs.readFileSync(outputPath, 'utf8').slice(0, 1500);
      }
      examples.push({ label: pair.label, rawSample, template });
    } catch (e) {}
  }
  return examples;
}

// ─── SYSTEM PROMPT v2 ───────────────────────────────────

const SYSTEM_PROMPT = `Sen banka ekstresi ve muhasebe defterleri için parser template üreten bir uzman AI'sın.

Görevin: Verilen ham dosya extract çıktısını analiz edip, parse için kullanılacak TEMPLATE JSON üretmek.

KRİTİK KURAL: Few-shot örneklerindeki x koordinatlarını, sütun pozisyonlarını veya regex pattern'lerini KOPYALAMA. Her dosyanın kendine özgü layoutu vardır. Tüm değerleri RAW DATA'DAN ÖLÇEREK tespit et.

CEVABIN İKİ KISIMDAN OLUŞACAK:

═══════════════════════════════════════════
KISIM 1 — ANALİZ (100-200 kelime, düz metin)
═══════════════════════════════════════════
Aşağıdaki soruları yanıtla:

1. FORMAT: PDF mi Excel mi? Landscape mi portrait? Kaç sayfa/sheet?
2. LOCALE:
   - Bir sayısal tutar örneği göster (raw data'dan kopyala)
   - Decimal separator: virgül mü nokta mı?
   - Thousand separator: boşluk mu virgül mü nokta mı?
   - Tarih formatı: örnek tarih göster → format çıkar
3. PDF İÇİN — KOLON ANALİZİ:
   - En az 3 transaction satırının textItems'larını incele
   - Her kolonun x aralığını ölç (x_min — x_max):
     * Tarih: x=?-?
     * Debit: x=?-?  (3 örnekten min/max al)
     * Credit: x=?-? (3 örnekten min/max al)
     * Counterparty: x=?-?
   - Debit ve credit x aralıkları çakışıyor mu? Aralarındaki mesafe?
4. EXCEL İÇİN — SECTION ANALİZİ:
   - Tek tablo mu, yoksa yanyana 2+ tablo mu? (cell adreslerine bak!)
   - Boş kolon var mı tablolar arasında? (F,G,H boşsa → dual section)
   - Her section hangi kolonları kullanıyor?
   - Transaction verisi kaçıncı satırdan başlıyor?
   - Sheet adı tarih mi? Format?
5. METADATA: Opening/closing balance, period, IBAN nerede?
6. PATTERN'LER: BIN (12 hane), IBAN (KZ ile başlayan), KNP kodu var mı?

═══════════════════════════════════════════
KISIM 2 — TEMPLATE JSON
═══════════════════════════════════════════
Analiz sonucuna göre template JSON üret.
MUTLAKA \`\`\`json ... \`\`\` code block içinde yaz.

TEMPLATE SCHEMA:
{
  "name": "string",
  "file_format": "pdf" | "xlsx",
  "country_code": "KZ" | "TR" | ...,
  "language_code": "ru" | "tr" | "en",
  "bank_name": "string | null",
  "bank_identifier": "SWIFT/BIC | null",
  "locale": {
    "decimal_separator": "." | ",",
    "thousand_separator": " " | "," | "." (decimal_separator'dan FARKLI!),
    "date_format": "DD.MM.YYYY" | "DD/MM/YYYY" | "YYYY-MM-DD"
  },
  "row_detection": {
    "method": "y_coordinate_grouping",
    "pattern": "regex — transaction başlangıç pattern'i",
    "y_tolerance": 2-6,
    "skip_header_y": number,
    "date_x_min": number, "date_x_max": number,
    "stop_pattern": "Итого|Total|Toplam"
  },
  "sections": [ ... ],
  "sheet_pattern": "regex",
  "sheet_date_format": "DD.MM.YYYY",
  "fields": {
    "transaction_date": { "method": "x_coordinate_range", "x_min": N, "x_max": N },
    "debit": { "method": "x_coordinate_range", "x_min": N, "x_max": N, "use_all_rows": true },
    "credit": { "method": "x_coordinate_range", "x_min": N, "x_max": N, "use_all_rows": true },
    "counterparty_name": { "method": "x_coordinate_range", "x_min": N, "x_max": N, "use_all_rows": true },
    "counterparty_bin": { "method": "regex_in_field", "pattern": "regex" },
    "payment_details": { ... },
    "knp_code": { ... },
    "external_reference": { ... }
  },
  "metadata": {
    "account_iban": { "method": "regex", "pattern": "..." },
    "opening_balance": { "method": "regex", "pattern": "..." },
    "closing_balance": { "method": "regex", "pattern": "..." },
    "period_start": { "method": "regex", "pattern": "...", "date_format": "..." },
    "period_end": { "method": "regex", "pattern": "...", "date_format": "..." }
  }
}

X KOORDİNAT TESPİTİ (PDF için):

Raw data'da textItems şöyle görünür:
{"text": "128 591,10", "x": 432.0, "y": 312.0, "w": 45.0}
{"text": "KZ5896503F0007358", "x": 162.0, "y": 308.0, "w": 80.0}

Aynı y'de (±tolerance) olan item'lar aynı satırdadır. Kolonları tespit etmek için:

1. Bir transaction satırındaki TÜM item'ları bul (aynı y ± 3-6)
2. x'lerini küçükten büyüğe sırala
3. Hangi item'ın hangi field olduğunu İÇERİĞİNDEN anla:
   - DD.MM.YYYY formatında → tarih
   - KZ ile başlayan 20+ karakter → IBAN
   - 12 haneli sayı → BIN
   - Sayısal tutar (locale'e uygun) → debit VEYA credit
   - 3 haneli sayı → KNP kodu
4. Aynı field'ın 3+ örneğinin x değerlerinden RANGE çıkar:
   x_min = min(x_values) - 5
   x_max = max(x_values) + max(width_values) + 5

DEBIT vs CREDIT AYIRIMI:
- Her iki kolon da sayısal tutar içerir
- İkisi genelde yan yana ama FARKLI x aralıklarında
- Debit solu, credit sağı (veya tersi) — birden fazla örneğe bak
- x aralıkları KESINLIKLE çakışmamalı

EXCEL DUAL-SECTION TESPİTİ:
- Eğer tek sheet'te B-E ve I-L gibi iki ayrı kolon grubu kullanılıyorsa → sections array kullan
- Ortadaki boş kolonlar (F,G,H) iki section'ı ayırır
- Her section için ayrı "columns" mapping yaz
- Sheet adı tarih ise → sheet_date_format ekle, transaction_date section'dan değil sheet adından gelir

METADATA REGEX YAZARKEN:
- Opening/closing balance: "Входящий остаток", "Исходящий остаток", "Devir bakiye" gibi label'ları ara
- IBAN: KZ ile başlayan 20 haneli, veya TR ile başlayan 26 haneli string
- Regex'te boşluk/whitespace esnek tut: \\s+ kullan`;

// ─── CLAUDE API CALL ────────────────────────────────────

async function callClaude(messages, apiKey, maxRetries = 2) {
  let lastError = null;
  let analysis = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const body = {
      model: 'claude-sonnet-4-20250514',
      max_tokens: 5000,
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

    // Extract analysis (text before JSON block) and JSON
    const jsonBlockMatch = text.match(/```json\s*([\s\S]*?)\s*```/);
    if (jsonBlockMatch) {
      analysis = text.slice(0, text.indexOf('```json')).trim();
      try {
        const template = JSON.parse(jsonBlockMatch[1]);
        return { template, analysis, tokens_used: usage, raw_response: text, attempts: attempt + 1 };
      } catch (parseErr) {
        lastError = `JSON parse error in code block: ${parseErr.message}`;
        console.error(`JSON parse failed (attempt ${attempt + 1}):`, parseErr.message);
      }
    } else {
      // No code block — try parsing entire response as JSON
      try {
        let jsonStr = text.trim();
        if (jsonStr.startsWith('```')) jsonStr = jsonStr.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
        const template = JSON.parse(jsonStr);
        return { template, analysis: '', tokens_used: usage, raw_response: text, attempts: attempt + 1 };
      } catch (parseErr) {
        lastError = `No JSON block found and raw parse failed: ${parseErr.message}`;
        analysis = text.slice(0, 500);
        console.error(`JSON not found (attempt ${attempt + 1})`);
      }
    }

    // Retry
    if (attempt < maxRetries) {
      messages = [
        ...messages,
        { role: 'assistant', content: text },
        { role: 'user', content: 'Cevabındaki JSON parse edilemedi. Lütfen KISIM 1 (analiz) yazıp, sonra ```json ... ``` code block içinde VALID JSON template döndür.' },
      ];
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
  if (!['pdf', 'xlsx', 'xls', 'csv', 'txt'].includes(template.file_format)) errors.push('file_format geçersiz');

  if (!template.locale) errors.push('locale eksik');
  else {
    if (!template.locale.decimal_separator) warnings.push('locale.decimal_separator eksik');
    if (template.locale.decimal_separator === template.locale.thousand_separator)
      errors.push('decimal_separator ve thousand_separator aynı olamaz');
    if (!template.locale.date_format) warnings.push('locale.date_format eksik');
  }

  if (!template.fields && !template.sections) errors.push('fields veya sections eksik');
  if (template.fields && !template.sections) {
    if (!template.fields.debit && !template.fields.credit) errors.push('fields.debit veya credit gerekli');
  }

  if (template.file_format === 'pdf' && !template.row_detection) warnings.push('PDF için row_detection önerilir');
  if (['xlsx', 'xls'].includes(template.file_format) && (!template.sections || !template.sections.length)) warnings.push('Excel için sections önerilir');

  return { valid: errors.length === 0, errors, warnings };
}

// ─── MAIN GENERATOR ─────────────────────────────────────

async function generateTemplate(rawExtract, fileInfo, anthropicApiKey) {
  const compressed = fileInfo.format === 'pdf'
    ? compressPdfExtract(rawExtract)
    : compressExcelExtract(rawExtract);

  const examples = loadFewShotExamples();
  let fewShotText = '';
  for (const ex of examples) {
    fewShotText += `\n--- ÖRNEK: ${ex.label} ---\nRAW EXTRACT ÖZETİ:\n${ex.rawSample}\n\nÜRETİLEN TEMPLATE:\n${JSON.stringify(ex.template, null, 2)}\n`;
  }

  // Cashbook dual-section vurgusu
  const dualSectionHint = fileInfo.format !== 'pdf' ? `
ÖNEMLİ — DUAL SECTION TESPİTİ:
Eğer sheet'te B-E kolonları (sol tablo) ve I-L kolonları (sağ tablo) gibi iki ayrı bölge varsa,
sections array KULLANMALISIN. Ortadaki boş kolonlar (F,G,H) iki section'ı ayırır.
Örnek: sections = [
  {"name": "cash", "columns": {"number":"B", "description":"C", "debit":"D", "credit":"E"}, "start_row": 7},
  {"name": "bank", "columns": {"number":"I", "description":"J", "debit":"K", "credit":"L"}, "start_row": 7}
]
Sheet adı tarih formatındaysa: "sheet_date_format": "DD.MM.YYYY"
` : '';

  const userMessage = `Bu bir ${fileInfo.target_module === 'bank_statement' ? 'BANKA EKSTRESİ' : 'KASA DEFTERİ'}.

FILE INFO: ${JSON.stringify(fileInfo)}

RAW EXTRACT:
${JSON.stringify(compressed, null, 2)}
${dualSectionHint}
REFERANS ÖRNEKLER (layoutları KOPYALAMA, sadece yapıyı anla):
${fewShotText}

Önce ANALİZ yap (KISIM 1), sonra \`\`\`json ... \`\`\` içinde TEMPLATE JSON üret (KISIM 2).`;

  const messages = [{ role: 'user', content: userMessage }];
  const result = await callClaude(messages, anthropicApiKey);

  const validation = validateTemplate(result.template);

  return {
    template: result.template,
    analysis: result.analysis || '',
    confidence: validation.valid ? (validation.warnings.length === 0 ? 'high' : 'medium') : 'low',
    validation,
    tokens_used: result.tokens_used,
    attempts: result.attempts,
  };
}

module.exports = { generateTemplate, validateTemplate, compressPdfExtract, compressExcelExtract };
