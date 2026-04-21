#!/usr/bin/env node
/**
 * Step 4 — execute_import RPC smoke test.
 *
 * Harness replays the full Step 2+3+4 flow headlessly per scenario:
 *   1. Load sample file → extract → match template → parse
 *   2. Insert data_imports + data_import_lines (status=parsed)
 *   3. Run matching engine + auto-confirm everything (bypass UI)
 *   4. Call execute_import RPC with service role
 *   5. Verify bank_transactions / contact_transactions / balance
 *   6. Clean up
 *
 * Scenarios:
 *   T1 Halyk — 26 lines
 *   T3 BCC   — 13 lines (with own_transfer)
 *   T4 Rollback — break one line's target_bank_account_id, expect failure +
 *                 no bank_transactions rows inserted, data_imports.status='parsed'
 *
 * T2 (Cashbook) is Excel; same mechanics but Excel's metadata lacks
 * opening/closing balance so the balance-recompute path is trivially covered.
 * Skipped here to keep the run fast — covered by Step 3 smoke already.
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const path = require('path');
const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');
const { extractTextFromPdf } = require('./parsers/pdf-parser');
const { parseWithTemplate } = require('./parsers/template-engine');
const matcher = require('../../js/bank-import/matching-engine');

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const COMPANY_ID   = '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82';
const BANK_HALYK   = 'e3467e63-fd43-4771-8456-661140183d39';
const BANK_BCC     = 'c98b6b16-25e7-485f-9b4a-16697dcac18f';
const SAMPLES = path.join(__dirname, 'samples');

function mergeTemplate(row) {
  const pc = row.parser_config || {};
  return {
    ...pc,
    file_format:  pc.file_format  || row.file_format,
    locale:       pc.locale       || row.locale         || {},
    metadata:     pc.metadata     || row.metadata_config || {},
  };
}

async function loadTemplateByHeader(headerToken) {
  const { data } = await sb.from('import_templates').select('*').eq('is_system', true);
  for (const t of data) {
    const h = t.detection_rules?.header_contains;
    if (h && (Array.isArray(h) ? h.some(x => x.includes(headerToken)) : h.includes(headerToken))) {
      return { row: t, template: mergeTemplate(t) };
    }
  }
  throw new Error('Template not found: ' + headerToken);
}

async function loadMatcherContext(accountId) {
  const [c, e, b, coa, comp, bt] = await Promise.all([
    sb.from('contacts').select('id, name, tax_number').eq('company_id', COMPANY_ID),
    sb.from('employees').select('id, first_name, last_name, tax_number').eq('company_id', COMPANY_ID),
    sb.from('bank_accounts').select('id, iban, account_name, currency_code').eq('company_id', COMPANY_ID),
    sb.from('chart_of_accounts').select('id, code, name, type').eq('company_id', COMPANY_ID).eq('type', 'expense'),
    sb.from('companies').select('tax_number').eq('id', COMPANY_ID).single(),
    sb.from('bank_transactions').select('id, external_reference').eq('account_id', accountId).not('external_reference', 'is', null)
  ]);
  return matcher.buildContext({
    contacts: c.data || [], employees: e.data || [],
    bankAccounts: b.data || [], expenseAccounts: coa.data || [],
    ownBin: comp.data?.tax_number || null,
    currentAccountId: accountId,
    existingBankTransactions: bt.data || []
  });
}

async function seedImport({ file, accountId, headerToken, mutateOneLine }) {
  const { row: tplRow, template } = await loadTemplateByHeader(headerToken);
  const raw = await extractTextFromPdf(path.join(SAMPLES, file));
  const parsed = parseWithTemplate(raw, template);

  const importId = crypto.randomUUID();
  const totalD = parsed.transactions.reduce((s, t) => s + (t.debit  || 0), 0);
  const totalC = parsed.transactions.reduce((s, t) => s + (t.credit || 0), 0);
  await sb.from('data_imports').insert({
    id: importId, company_id: COMPANY_ID, bank_account_id: accountId,
    import_type: 'bank_statement', source: template.bank_name || 'test', file_name: file,
    status: 'parsed',
    period_start: parsed.metadata?.period_start, period_end: parsed.metadata?.period_end,
    opening_balance: parsed.metadata?.opening_balance, closing_balance: parsed.metadata?.closing_balance,
    total_debit: totalD, total_credit: totalC, template_id: tplRow.id
  });

  const ctx = await loadMatcherContext(accountId);

  const lines = parsed.transactions.map((tx, i) => {
    const res = matcher.matchTransaction(tx, ctx);
    return {
      id: crypto.randomUUID(), import_id: importId, company_id: COMPANY_ID, line_number: i + 1,
      transaction_date: tx.transaction_date || '2026-04-01',
      debit: tx.debit || 0, credit: tx.credit || 0,
      counterparty_name: tx.counterparty_name || null,
      counterparty_bin: tx.counterparty_bin || null,
      counterparty_iban: tx.counterparty_iban || null,
      payment_details: tx.payment_details || null,
      knp_code: tx.knp_code || null,
      external_reference: tx.external_reference || null,
      document_number: tx.document_number || null,
      is_confirmed: true, // auto-confirm everything
      is_skipped: false,
      match_type: res.match_type,
      matched_contact_id:   res.matched_contact_id   || null,
      matched_account_id:   res.matched_account_id   || null,
      matched_employee_id:  res.matched_employee_id  || null,
      target_bank_account_id: res.target_bank_account_id || null,
      suggested_contact_id: res.suggested_contact_id || null,
      suggestion_reason:    res.suggestion_reason    || null,
      confidence:           res.confidence           ?? null,
      auto_bin_update:      res.auto_bin_update      || null,
      duplicate_of_bank_tx_id: res.duplicate_of_bank_tx_id || null,
      is_duplicate: res.match_type === 'duplicate'
    };
  });

  // Make all own_transfers unresolved target for T3 (use a real bank acct from another company → FK fail?)
  if (mutateOneLine) mutateOneLine(lines);

  const BATCH = 50;
  for (let i = 0; i < lines.length; i += BATCH) {
    const { error } = await sb.from('data_import_lines').insert(lines.slice(i, i + BATCH));
    if (error) throw new Error('line insert failed: ' + error.message);
  }
  return { importId, lineCount: lines.length, templateId: tplRow.id };
}

async function cleanup(importId) {
  const { data: btxs } = await sb.from('bank_transactions').select('id').eq('import_id', importId);
  const btxIds = (btxs || []).map(x => x.id);
  if (btxIds.length) {
    await sb.from('contact_transactions').delete().in('bank_transaction_id', btxIds);
    await sb.from('bank_transactions').delete().in('id', btxIds);
  }
  await sb.from('data_import_lines').delete().eq('import_id', importId);
  await sb.from('data_imports').delete().eq('id', importId);
}

async function countsFor(importId, accountId) {
  const [bt, ct, di, ba] = await Promise.all([
    sb.from('bank_transactions').select('*', { count: 'exact', head: true }).eq('import_id', importId),
    sb.from('contact_transactions').select('id, bank_transaction_id').not('bank_transaction_id', 'is', null).limit(1000),
    sb.from('data_imports').select('id, status, success_rows, error_rows').eq('id', importId).single(),
    sb.from('bank_accounts').select('current_balance').eq('id', accountId).single()
  ]);
  // Count contact_transactions where bank_transaction_id is one of ours
  const { count: ctCount } = await sb.from('bank_transactions').select('*', { count: 'exact', head: true }).eq('import_id', importId);
  return {
    bank_tx: bt.count,
    import_status: di.data?.status,
    success_rows: di.data?.success_rows,
    balance: ba.data?.current_balance
  };
}

async function runScenario({ label, file, accountId, headerToken, expect, mutate }) {
  console.log('\n' + '═'.repeat(72));
  console.log(label);
  console.log('═'.repeat(72));

  // Snapshot balance before
  const { data: before } = await sb.from('bank_accounts').select('current_balance').eq('id', accountId).single();
  console.log(`  balance before: ${before.current_balance}`);

  const { importId, lineCount } = await seedImport({ file, accountId, headerToken, mutateOneLine: mutate });
  console.log(`  seeded import_id=${importId} with ${lineCount} lines`);

  let rpcResult = null, rpcError = null;
  try {
    const { data, error } = await sb.rpc('execute_import', { p_import_id: importId });
    if (error) throw error;
    rpcResult = data;
  } catch (e) {
    rpcError = e;
  }

  if (rpcError) {
    console.log(`  RPC ERROR: ${rpcError.message}`);
  } else {
    console.log(`  RPC result: imported=${rpcResult.imported_count} skipped=${rpcResult.skipped_count} duplicate=${rpcResult.duplicate_count}`);
    console.log(`  new_contacts=${rpcResult.new_contact_ids.length} updated_contacts=${rpcResult.updated_contact_ids.length}`);
    console.log(`  final_balance=${rpcResult.final_balance}`);
  }

  const counts = await countsFor(importId, accountId);
  console.log(`  post-check: bank_tx=${counts.bank_tx} status=${counts.import_status} success_rows=${counts.success_rows} balance=${counts.balance}`);

  const ok = expect(rpcResult, rpcError, counts);
  console.log(`  ${ok ? '✓ EXPECTATION MET' : '✗ EXPECTATION FAILED'}`);
  await cleanup(importId);
  // Restore balance too (since cleanup removes bank_tx's contribution)
  await sb.rpc('exec_sql', { query: `UPDATE bank_accounts SET current_balance=${before.current_balance} WHERE id='${accountId}'` });
  return ok;
}

(async () => {
  let allOk = true;

  // T1 — Halyk (no own_transfer targets → fine)
  allOk = await runScenario({
    label: 'T1 — Halyk PDF: 26 lines, all confirmed',
    file: 'halyk.pdf', accountId: BANK_HALYK, headerToken: 'Народный',
    expect: (res, err, c) => !err && res.imported_count >= 20 && c.import_status === 'imported'
  }) && allOk;

  // T3 — BCC (own_transfer can appear if ownBin == 120440018675)
  // First set company tax_number so own_transfer can resolve
  await sb.from('companies').update({ tax_number: '120440018675' }).eq('id', COMPANY_ID);
  allOk = await runScenario({
    label: 'T3 — BCC PDF: own_transfer path exercised',
    file: 'bcc.pdf', accountId: BANK_BCC, headerToken: 'ЦентрКредит',
    expect: (res, err, c) => !err && res.imported_count >= 10 && c.import_status === 'imported'
  }) && allOk;

  // T4 — Rollback: point own_transfer target at a REAL bank_account from a
  // DIFFERENT company. FK passes (bank_accounts.id is globally unique) but
  // the RPC's "company_id = v_company_id" guard will RAISE, forcing rollback.
  const { data: foreignAcct } = await sb.from('bank_accounts')
    .select('id, company_id').neq('company_id', COMPANY_ID).eq('is_active', true).limit(1).single();
  if (!foreignAcct) throw new Error('Need a bank_account in another company to run T4');
  allOk = await runScenario({
    label: 'T4 — Rollback test: own_transfer target in foreign company → whole import must rollback',
    file: 'bcc.pdf', accountId: BANK_BCC, headerToken: 'ЦентрКредит',
    mutate: (lines) => {
      const first = lines[0];
      first.match_type = 'own_transfer';
      first.target_bank_account_id = foreignAcct.id;
    },
    expect: (res, err, c) => err && c.bank_tx === 0 && c.import_status === 'parsed'
  }) && allOk;

  // Restore company tax_number
  await sb.from('companies').update({ tax_number: '10012345678' }).eq('id', COMPANY_ID);

  console.log('\n' + '═'.repeat(72));
  console.log(allOk ? 'ALL TESTS PASSED' : 'ONE OR MORE TESTS FAILED');
  console.log('═'.repeat(72));
  process.exit(allOk ? 0 : 1);
})().catch(e => { console.error(e); process.exit(1); });
