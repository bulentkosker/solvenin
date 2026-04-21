#!/usr/bin/env node
/**
 * Smoke test: bank-import.html Step 1 + Step 2 akışını Node'da kopyalar.
 *
 * Tests:
 *  A — Halyk PDF: system template match, AI yok, parse, balance check, DB insert
 *  B — Cashbook Excel: generic-cashbook match, multi-sheet parse, DB insert
 *  C — BCC PDF (AI fallback): detection_rules nuke → claude-proxy → template üret → parse → DB insert → rules restore
 *
 * NOT: Browser'dan farklı olarak service key + direct DB erişimi kullanır (auth yok).
 * Template match + parse + insert mantığı bank-import.html ile birebir aynıdır.
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');
const { extractTextFromPdf } = require('./parsers/pdf-parser');
const { extractSheetsFromExcel } = require('./parsers/excel-parser');
const { parseWithTemplate } = require('./parsers/template-engine');

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

// Fixed test fixtures (from db-probe)
const COMPANY_ID = '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82'; // ANKA GROUP TR
const BANK_ACCOUNT_HALYK = 'e3467e63-fd43-4771-8456-661140183d39';
const BANK_ACCOUNT_BCC   = 'c98b6b16-25e7-485f-9b4a-16697dcac18f';
const BANK_ACCOUNT_CASH  = 'e3467e63-fd43-4771-8456-661140183d39'; // any active bank account

const SAMPLES = path.join(__dirname, 'samples');

// ─── MIRROR OF bank-import.html findMatchingTemplate (post-fix) ─────
async function findMatchingTemplate(rawData, format) {
  const { data: templates } = await sb.from('import_templates')
    .select('*')
    .in('target_module', ['bank_statement', 'cash_register'])
    .eq('file_format', format)
    .is('deleted_at', null);
  if (!templates?.length) return { template: null, debug: 'no templates in DB for this format+module' };

  const allText = format === 'pdf'
    ? rawData.pages?.map(p => p.text).join(' ')
    : rawData.sheets?.map(s => s.rows?.flat()?.join(' ')).join(' ');

  for (const t of templates) {
    const rules = t.detection_rules || {};
    let matched = false;
    let matchedBy = null;

    if (rules.header_contains) {
      if (Array.isArray(rules.header_contains)) {
        matched = rules.header_contains.some(h => allText.includes(h));
      } else {
        matched = allText.includes(rules.header_contains);
      }
      if (matched) matchedBy = 'header_contains';
    }

    if (!matched && rules.bank_identifier_pattern) {
      matched = new RegExp(rules.bank_identifier_pattern).test(allText);
      if (matched) matchedBy = 'bank_identifier_pattern';
    }

    if (matched) return { template: mergeTemplate(t), debug: `${matchedBy} match on: ${t.name}`, templateRow: t };
  }
  return { template: null, debug: `no match among ${templates.length} candidates` };
}

function mergeTemplate(row) {
  const pc = row.parser_config || {};
  return {
    ...pc,
    name:          pc.name          || row.name,
    file_format:   pc.file_format   || row.file_format,
    target_module: pc.target_module || row.target_module,
    bank_name:     pc.bank_name     || row.bank_name,
    locale:        pc.locale        || row.locale         || {},
    metadata:      pc.metadata      || row.metadata_config || {},
  };
}

// ─── MIRROR OF bank-import.html generateTemplateViaProxy ────────────
async function generateTemplateViaProxy(rawData, fileInfo) {
  const compressed = fileInfo.format === 'pdf'
    ? { pages: rawData.pages?.slice(0, 2).map(p => ({ pageNumber: p.pageNumber, text: p.text?.slice(0, 2000), textItems: p.textItems?.slice(0, 150).map(ti => ({ text: ti.text, x: Math.round(ti.x), y: Math.round(ti.y), w: Math.round(ti.width) })) })) }
    : { sheets: rawData.sheets?.slice(0, 3).map(s => ({ sheetName: s.sheetName, rows: s.rows?.slice(0, 25), merges: s.merges?.slice(0, 10) })) };

  const { data, error } = await sb.functions.invoke('claude-proxy', {
    body: { mode: 'template_generation', raw_extract: compressed, file_info: fileInfo, companyId: COMPANY_ID }
  });
  if (error) throw new Error('claude-proxy error: ' + error.message);
  if (data?.error) throw new Error('claude-proxy returned error: ' + data.error);
  return { template: data?.template || null, validation_warnings: data?.validation_warnings || [] };
}

// ─── MAIN RUNNER ────────────────────────────────────────────────────
async function runTest({ name, file, accountId, expectAI, beforeHook, afterHook }) {
  console.log(`\n${'═'.repeat(72)}`);
  console.log(`TEST: ${name}`);
  console.log(`  file: ${file}`);
  console.log('═'.repeat(72));
  const errors = [];
  const steps = {};

  try {
    if (beforeHook) await beforeHook();

    const filePath = path.join(SAMPLES, file);
    if (!fs.existsSync(filePath)) { errors.push({ step: 'fixture', msg: 'sample not found: ' + filePath }); return { name, errors, steps }; }

    const isPdf = file.toLowerCase().endsWith('.pdf');
    const format = isPdf ? 'pdf' : 'xlsx';
    steps.format = format;

    // Step 1: file (skip storage upload in Node — would need browser path)
    const importId = crypto.randomUUID();
    steps.importId = importId;

    // Step 2a: extract
    const t0 = Date.now();
    const rawData = isPdf ? await extractTextFromPdf(filePath) : extractSheetsFromExcel(filePath);
    steps.extract_ms = Date.now() - t0;
    steps.extract = isPdf ? `${rawData.pages.length} pages` : `${rawData.sheets.length} sheets`;

    // Step 2b: find template
    const match = await findMatchingTemplate(rawData, format);
    steps.match_debug = match.debug;
    let template = match.template;
    let templateRow = match.templateRow;
    let usedAI = false;

    // Step 2c: AI fallback if no match
    if (!template) {
      console.log('  → no system template matched, invoking claude-proxy (AI)…');
      const t1 = Date.now();
      const aiResult = await generateTemplateViaProxy(rawData, {
        filename: file, format, size: fs.statSync(filePath).size, target_module: 'bank_statement'
      });
      steps.ai_ms = Date.now() - t1;
      steps.ai_validation_warnings = aiResult.validation_warnings;
      const aiTemplate = aiResult.template;
      if (aiTemplate) {
        template = aiTemplate;
        usedAI = true;
        const { data: savedTpl, error: saveErr } = await sb.from('import_templates').insert({
          company_id: COMPANY_ID,
          name: template.name || `AI — ${file}`,
          file_format: template.file_format || format,
          target_module: 'bank_statement',
          parser_config: template,
          locale: template.locale || {},
          is_ai_generated: true,
          is_system: false
        }).select('id').single();
        if (saveErr) errors.push({ step: 'save AI template', msg: saveErr.message });
        steps.ai_template_id = savedTpl?.id;
      }
    }
    if (expectAI && !usedAI) errors.push({ step: 'AI expected', msg: 'Expected AI fallback but system template matched' });
    if (!expectAI && usedAI) errors.push({ step: 'AI not expected', msg: 'Expected system template match but went to AI' });

    if (!template) { errors.push({ step: 'template', msg: 'no template found & AI failed' }); return { name, errors, steps }; }

    steps.template_name = template.name || '(no name field in parser_config)';
    steps.template_file_format = template.file_format || '(missing!)';

    // Step 2d: parse
    const parsed = parseWithTemplate(rawData, template);
    steps.tx_count = parsed.transactions?.length || 0;
    steps.warnings = parsed.warnings?.slice(0, 3) || [];
    if (!parsed.transactions?.length) errors.push({ step: 'parse', msg: 'zero transactions parsed' });

    // Step 2e: balance check (reuse engine's checkBalance if available)
    const opening = parsed.metadata?.opening_balance;
    const closing = parsed.metadata?.closing_balance;
    const totalDebit  = parsed.transactions.reduce((s, t) => s + (t.debit  || 0), 0);
    const totalCredit = parsed.transactions.reduce((s, t) => s + (t.credit || 0), 0);
    let balance = { ok: null };
    if (opening != null && closing != null) {
      const actual = opening + totalCredit - totalDebit;
      const tolerance = Math.max(0.02, Math.abs(opening) * 0.0001);
      balance = { ok: Math.abs(actual - closing) <= tolerance, expected: closing, actual, diff: actual - closing };
    }
    steps.balance = balance;
    steps.totalDebit = totalDebit;
    steps.totalCredit = totalCredit;

    // Step 2f: DB insert (same as browser)
    const { data: importRow, error: impErr } = await sb.from('data_imports').insert({
      id: importId, company_id: COMPANY_ID, bank_account_id: accountId,
      import_type: 'bank_statement', source: template.bank_name || 'unknown',
      file_name: file, status: 'parsed',
      period_start: parsed.metadata?.period_start || null,
      period_end: parsed.metadata?.period_end || null,
      opening_balance: parsed.metadata?.opening_balance ?? null,
      closing_balance: parsed.metadata?.closing_balance ?? null,
      total_debit: totalDebit, total_credit: totalCredit,
      template_id: templateRow?.id || null
    }).select('id').single();
    if (impErr) errors.push({ step: 'insert data_imports', msg: impErr.message });
    steps.db_import_id = importRow?.id;

    if (parsed.transactions.length && importRow) {
      const lines = parsed.transactions.map((tx, i) => ({
        import_id: importRow.id, company_id: COMPANY_ID, line_number: i + 1,
        transaction_date: tx.transaction_date || new Date().toISOString().split('T')[0],
        debit: tx.debit || 0, credit: tx.credit || 0,
        counterparty_name: tx.counterparty_name || null,
        counterparty_bin: tx.counterparty_bin || null,
        payment_details: tx.payment_details || tx.description || null,
        knp_code: tx.knp_code || null,
        external_reference: tx.external_reference || null,
        document_number: tx.document_number || null,
        match_type: 'unmatched'
      }));
      const BATCH = 100;
      for (let i = 0; i < lines.length; i += BATCH) {
        const { error } = await sb.from('data_import_lines').insert(lines.slice(i, i + BATCH));
        if (error) errors.push({ step: 'insert data_import_lines', msg: error.message });
      }
    }

    return { name, errors, steps, usedAI };
  } catch (e) {
    errors.push({ step: 'runner', msg: e.message });
    console.error(e);
    return { name, errors, steps };
  } finally {
    if (afterHook) await afterHook();
  }
}

// ─── ENTRY ──────────────────────────────────────────────────────────
(async () => {
  const results = [];

  // TEST A — Halyk PDF (system template expected)
  results.push(await runTest({
    name: 'A — Halyk PDF (system template)',
    file: 'halyk.pdf',
    accountId: BANK_ACCOUNT_HALYK,
    expectAI: false
  }));

  // TEST B — Cashbook Excel (generic-cashbook expected)
  results.push(await runTest({
    name: 'B — Cashbook XLSX (generic-cashbook)',
    file: 'cashbook.xlsx',
    accountId: BANK_ACCOUNT_CASH,
    expectAI: false
  }));

  // TEST C — BCC PDF with AI fallback (nuke detection_rules temporarily)
  let originalBccRules = null;
  results.push(await runTest({
    name: 'C — BCC PDF (AI fallback)',
    file: 'bcc.pdf',
    accountId: BANK_ACCOUNT_BCC,
    expectAI: true,
    beforeHook: async () => {
      const { data } = await sb.from('import_templates')
        .select('id, detection_rules').ilike('name', '%BCC%').eq('is_system', true).maybeSingle();
      if (!data) throw new Error('BCC template not found in DB');
      originalBccRules = { detection_rules: data.detection_rules, id: data.id };
      console.log(`  → nuking BCC detection_rules (id=${data.id})`);
      const { error } = await sb.from('import_templates').update({ detection_rules: {} }).eq('id', data.id);
      if (error) throw new Error('nuke failed: ' + error.message);
    },
    afterHook: async () => {
      if (originalBccRules) {
        const { error } = await sb.from('import_templates')
          .update({ detection_rules: originalBccRules.detection_rules })
          .eq('id', originalBccRules.id);
        if (error) console.error('  ⚠ restore BCC failed:', error.message);
        else console.log('  → BCC detection_rules restored');
      }
    }
  }));

  // ─── REPORT ─────────────────────────────────
  console.log(`\n${'═'.repeat(72)}`);
  console.log('SUMMARY');
  console.log('═'.repeat(72));
  for (const r of results) {
    const ok = r.errors.length === 0 && (r.steps.tx_count || 0) > 0;
    console.log(`\n[${ok ? 'PASS' : 'FAIL'}] ${r.name}`);
    console.log(`  steps:`, JSON.stringify(r.steps, null, 2).split('\n').join('\n  '));
    if (r.errors.length) {
      console.log('  ERRORS:');
      r.errors.forEach(e => console.log(`    • ${e.step}: ${e.msg}`));
    }
  }

  const failed = results.filter(r => r.errors.length || !(r.steps.tx_count > 0));
  process.exit(failed.length ? 1 : 0);
})().catch(e => { console.error('FATAL:', e); process.exit(2); });
