#!/usr/bin/env node
// End-to-end: cash/bank tx kategorili INSERT, transfer RPC, legacy rows.
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { persistSession: false } });

const COMPANY = '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82';

async function snap(id, table, col='current_balance') {
  const { data } = await sb.from(table === 'cash' ? 'cash_registers' : 'bank_accounts').select(col).eq('id', id).single();
  return Number(data[col]);
}

(async () => {
  const { data: reg } = await sb.from('cash_registers').select('id').eq('company_id', COMPANY).eq('is_active', true).limit(1).single();
  const { data: bank } = await sb.from('bank_accounts').select('id').eq('company_id', COMPANY).eq('is_active', true).limit(1).single();
  const { data: coa } = await sb.from('chart_of_accounts').select('id, code, name_local, type, parent_id')
    .eq('company_id', COMPANY).in('type', ['expense','cost','revenue','liability','asset']).eq('is_active', true).is('deleted_at', null);
  const parentIds = new Set(coa.map(a => a.parent_id).filter(Boolean));
  const leaf = (t) => coa.find(a => a.type === t && !parentIds.has(a.id));
  const expenseAcc = leaf('expense') || leaf('cost');
  const revenueAcc = leaf('revenue');

  const regBefore = await snap(reg.id, 'cash');
  const bankBefore = await snap(bank.id, 'bank');
  console.log('Before — cash:', regBefore, 'bank:', bankBefore);

  // T1: normal expense row
  const { data: expTx, error: expErr } = await sb.from('cash_transactions').insert({
    company_id: COMPANY, register_id: reg.id, type: 'out', amount: 50,
    currency_code: 'KZT', description: 'SMOKE expense', category: 'expense',
    transaction_date: '2026-04-23', source_type: 'manual',
    chart_of_account_id: expenseAcc.id
  }).select('id').single();
  if (expErr) throw expErr;
  console.log('T1 expense inserted:', expTx.id);

  // T2: salary with employee_id (if employees exist)
  const { data: emp } = await sb.from('employees').select('id').eq('company_id', COMPANY).limit(1).maybeSingle();
  if (emp) {
    const { error } = await sb.from('cash_transactions').insert({
      company_id: COMPANY, register_id: reg.id, type: 'out', amount: 100,
      currency_code: 'KZT', description: 'SMOKE salary', category: 'salary',
      transaction_date: '2026-04-23', source_type: 'manual',
      chart_of_account_id: expenseAcc.id, employee_id: emp.id
    });
    if (error) throw error;
    console.log('T2 salary with employee_id inserted');
  } else {
    console.log('T2 SKIP — no employees for this company');
  }

  // T3: transfer via RPC, then edit desc, then rollback test (same accts)
  const groupId = crypto.randomUUID();
  const { error: tErr } = await sb.rpc('execute_cash_bank_transfer', {
    p_group_id: groupId, p_company_id: COMPANY,
    p_source_type: 'cash', p_source_id: reg.id,
    p_target_type: 'bank', p_target_id: bank.id,
    p_amount: 200, p_date: '2026-04-23',
    p_description: 'SMOKE transfer', p_reference: 'R-1'
  });
  if (tErr) throw tErr;
  const { data: sides } = await sb.from('cash_transactions').select('id, category, transfer_group_id').eq('transfer_group_id', groupId);
  const { data: sides2 } = await sb.from('bank_transactions').select('id, category, transfer_group_id').eq('transfer_group_id', groupId);
  console.log('T3 transfer — cash side:', sides?.length, 'bank side:', sides2?.length, 'categories:', sides[0]?.category, sides2[0]?.category);

  // Same-acct rollback
  const { error: dupErr } = await sb.rpc('execute_cash_bank_transfer', {
    p_group_id: crypto.randomUUID(), p_company_id: COMPANY,
    p_source_type: 'cash', p_source_id: reg.id, p_target_type: 'cash', p_target_id: reg.id,
    p_amount: 1, p_date: '2026-04-23', p_description: 'dup'
  });
  console.log('T3 same-acct rejected:', dupErr ? '✓' : '✗');

  // Balance after everything
  const regAfter = await snap(reg.id, 'cash');
  const bankAfter = await snap(bank.id, 'bank');
  console.log('After — cash:', regAfter, '(delta', regAfter - regBefore, ')  bank:', bankAfter, '(delta', bankAfter - bankBefore, ')');

  // Cleanup
  await sb.from('cash_transactions').delete().eq('id', expTx.id);
  if (emp) await sb.from('cash_transactions').delete().eq('description', 'SMOKE salary').eq('employee_id', emp.id);
  await sb.from('cash_transactions').delete().eq('transfer_group_id', groupId);
  await sb.from('bank_transactions').delete().eq('transfer_group_id', groupId);
  const regEnd = await snap(reg.id, 'cash');
  const bankEnd = await snap(bank.id, 'bank');
  console.log('After cleanup — cash:', regEnd, 'bank:', bankEnd, '(should match before)');
  console.log(regEnd === regBefore && bankEnd === bankBefore ? '✓ balances restored' : '✗ balance leaked');
})().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
