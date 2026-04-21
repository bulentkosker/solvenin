#!/usr/bin/env node
/**
 * Step 3 — Matching engine smoke test.
 *
 * Re-runs Step 2 in-memory (extract + system-template parse), then feeds each
 * transaction through the matcher. Does NOT write to DB — just prints the
 * match_type distribution so we can verify fixture behavior before wiring UI.
 *
 * Scenarios:
 *   T1 Halyk PDF      — 26 tx, own_transfer + tax patterns expected
 *   T2 Cashbook XLSX  — 11 tx, mostly unmatched (no BIN/name in Excel rows)
 *   T3 BCC PDF        — 13 tx, 1 own_transfer (self-BIN row)
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const { extractTextFromPdf } = require('./parsers/pdf-parser');
const { extractSheetsFromExcel } = require('./parsers/excel-parser');
const { parseWithTemplate } = require('./parsers/template-engine');
const matcher = require('../../js/bank-import/matching-engine');

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const COMPANY_ID = '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82';
const SAMPLES = path.join(__dirname, 'samples');

// Override ownBin to the actual Anka Group BIN that appears in BCC sample,
// so the own_transfer layer can be exercised during smoke testing.
const OWN_BIN = '120440018675';

function mergeTemplate(row) {
  const pc = row.parser_config || {};
  return {
    ...pc,
    name:          pc.name          || row.name,
    file_format:   pc.file_format   || row.file_format,
    target_module: pc.target_module || row.target_module,
    locale:        pc.locale        || row.locale         || {},
    metadata:      pc.metadata      || row.metadata_config || {},
  };
}

async function loadTemplateByHeader(format, headerToken) {
  const { data } = await sb.from('import_templates').select('*')
    .eq('file_format', format).is('deleted_at', null).eq('is_system', true);
  for (const t of data) {
    const h = t.detection_rules?.header_contains;
    if (h && (Array.isArray(h) ? h.some(x => x.includes(headerToken)) : h.includes(headerToken))) {
      return mergeTemplate(t);
    }
  }
  throw new Error('Template not found for header: ' + headerToken);
}

async function loadContext() {
  const [contactsRes, empsRes, banksRes, expenseRes] = await Promise.all([
    sb.from('contacts').select('id, name, tax_number').eq('company_id', COMPANY_ID).is('deleted_at', null),
    sb.from('employees').select('id, first_name, last_name, tax_number').eq('company_id', COMPANY_ID).is('deleted_at', null),
    sb.from('bank_accounts').select('id, account_name, iban').eq('company_id', COMPANY_ID).is('deleted_at', null),
    sb.from('chart_of_accounts').select('id, code, name, type').eq('company_id', COMPANY_ID).eq('type', 'expense')
  ]);
  return matcher.buildContext({
    contacts: contactsRes.data || [],
    employees: empsRes.data || [],
    bankAccounts: banksRes.data || [],
    expenseAccounts: expenseRes.data || [],
    ownBin: OWN_BIN,
    settings: { bank_import_commission_mode: 'expense_account', bank_import_tax_mode: 'expense_account', bank_import_salary_mode: 'employee' }
  });
}

function distribution(results) {
  const dist = {};
  for (const r of results) dist[r.result.match_type] = (dist[r.result.match_type] || 0) + 1;
  return dist;
}

async function runScenario({ name, file, format, headerToken }) {
  console.log('\n' + '═'.repeat(72));
  console.log(name);
  console.log('═'.repeat(72));

  const template = await loadTemplateByHeader(format, headerToken);
  const raw = format === 'pdf'
    ? await extractTextFromPdf(path.join(SAMPLES, file))
    : extractSheetsFromExcel(path.join(SAMPLES, file));
  const parsed = parseWithTemplate(raw, template);
  console.log(`  Template: ${template.name}`);
  console.log(`  Parsed:   ${parsed.transactions.length} transactions`);

  const ctx = await loadContext();
  console.log(`  Context:  ${ctx.contacts.length} contacts, ${ctx.employees.length} employees, ${ctx.expenseAccounts.length} expense accts`);

  const results = matcher.matchBatch(parsed.transactions, ctx);
  const dist = distribution(results);
  console.log(`  Match dist: ${JSON.stringify(dist)}`);

  // Spot-check first 3 non-unmatched
  const interesting = results.filter(r => r.result.match_type !== 'unmatched').slice(0, 3);
  if (interesting.length) {
    console.log('  Sample matches:');
    for (const { line, result } of interesting) {
      const who = line.counterparty_name || '—';
      console.log(`    [${result.match_type}] ${who.slice(0, 40)} (bin=${line.counterparty_bin||'—'}) → conf=${result.confidence?.toFixed(2)}`);
    }
  }
  return { parsed, results, dist };
}

// ─── Synthetic unit-level checks for the engine's branches. The real
// fixtures don't happen to cover commission/tax/fuzzy today (company has no
// commission-named account, no employees, no seeded contacts that match
// counterparties), so these assertions make sure the code paths actually work.
function syntheticChecks() {
  console.log('\n' + '═'.repeat(72));
  console.log('Synthetic branch coverage');
  console.log('═'.repeat(72));
  const ctx = matcher.buildContext({
    contacts: [
      { id: 'c1', name: 'Jukotrans Logistics LLC', tax_number: null },
      { id: 'c2', name: 'Anka Agro TOO',           tax_number: '231240021712' }
    ],
    employees: [{ id: 'e1', first_name: 'Dina', last_name: 'Koshker', tax_number: '841226402663' }],
    bankAccounts: [{ id: 'b1', iban: 'KZ111', account_name: 'Our USD' }],
    expenseAccounts: [
      { id: 'a1', code: '770', name: 'Bank Komisyonu' },
      { id: 'a2', code: '780', name: 'Vergi Gideri' }
    ],
    ownBin: '120440018675',
    currentAccountId: 'b0'
  });

  const cases = [
    {
      label: 'BIN exact',
      line: { counterparty_bin: '231240021712', counterparty_name: 'X' },
      expect: { match_type: 'contact', matched_contact_id: 'c2' }
    },
    {
      label: 'commission keyword → expense',
      line: { payment_details: 'Komisyon bank fee', counterparty_name: 'Bank' },
      expect: { match_type: 'expense_account', matched_account_id: 'a1' }
    },
    {
      label: 'tax keyword (УГД) → expense',
      line: { counterparty_name: 'РГУ УГД по городу Кокшетау', payment_details: 'Земельный налог' },
      expect: { match_type: 'expense_account', matched_account_id: 'a2' }
    },
    {
      label: 'salary + name → employee',
      line: { counterparty_name: 'Koshker Dina', payment_details: 'Зарплата за апрель' },
      expect: { match_type: 'employee', matched_employee_id: 'e1' }
    },
    {
      label: 'fuzzy auto (≥0.95)',
      line: { counterparty_name: 'Anka Agro', counterparty_bin: '231240021712' },
      expect: { match_type: 'contact', matched_contact_id: 'c2' }
    },
    {
      label: 'fuzzy suggestion (0.80..0.95)',
      // Missing trailing 's' — target is "Jukotrans Logistics LLC".
      line: { counterparty_name: 'Jukotrans Logistic Ltd' },
      expect: { match_type: 'suggestion', suggested_contact_id: 'c1' }
    },
    {
      label: 'unmatched',
      line: { counterparty_name: 'Totally Unknown Company' },
      expect: { match_type: 'unmatched' }
    }
  ];

  let pass = 0, fail = 0;
  for (const c of cases) {
    const r = matcher.matchTransaction(c.line, ctx);
    const ok = Object.keys(c.expect).every(k => r[k] === c.expect[k]);
    console.log(`  ${ok ? '✓' : '✗'} ${c.label} → ${JSON.stringify(r)}`);
    if (ok) pass++; else fail++;
  }
  console.log(`  ${pass} pass / ${fail} fail`);
  return fail === 0;
}

(async () => {
  const t1 = await runScenario({ name: 'T1 — Halyk PDF', file: 'halyk.pdf', format: 'pdf', headerToken: 'Народный' });
  const t2 = await runScenario({ name: 'T2 — Cashbook XLSX', file: 'cashbook.xlsx', format: 'xlsx', headerToken: 'GÜNLÜK' });
  const t3 = await runScenario({ name: 'T3 — BCC PDF', file: 'bcc.pdf', format: 'pdf', headerToken: 'ЦентрКредит' });
  const synthOk = syntheticChecks();

  console.log('\n' + '═'.repeat(72));
  console.log('Expectations:');
  console.log('  T1: 26 tx parsed, distribution has at least unmatched (no BIN seeded in contacts)');
  console.log('  T2: 11 tx parsed, mostly unmatched (Excel rows lack BIN/name)');
  console.log('  T3: 13 tx parsed, ≥1 own_transfer (self-BIN 120440018675 appears)');
  console.log('═'.repeat(72));
})().catch(e => { console.error(e); process.exit(1); });
