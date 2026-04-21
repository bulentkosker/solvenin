#!/usr/bin/env node
require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });

(async () => {
  const { data: imports } = await sb.from('data_imports')
    .select('id, file_name, source, status, period_start, period_end, total_debit, total_credit, created_at')
    .order('created_at', { ascending: false }).limit(3);

  console.log('\n── Son 3 data_imports ──');
  for (const imp of imports || []) {
    const { count } = await sb.from('data_import_lines').select('*', { count: 'exact', head: true }).eq('import_id', imp.id);
    console.log(`  [${imp.created_at?.slice(0,19)}] ${imp.file_name} (${imp.source})`);
    console.log(`    id=${imp.id} status=${imp.status}`);
    console.log(`    period=${imp.period_start||'—'}/${imp.period_end||'—'} debit=${imp.total_debit} credit=${imp.total_credit}`);
    console.log(`    lines=${count}`);
  }

  const ids = (imports || []).map(i => i.id);
  if (ids.length) {
    const { data: sampleLines } = await sb.from('data_import_lines')
      .select('import_id, line_number, transaction_date, debit, credit, counterparty_name')
      .in('import_id', ids).order('line_number').limit(5);
    console.log('\n── İlk 5 data_import_lines (en yeni importlerden) ──');
    sampleLines?.forEach(l => console.log(`  [${l.line_number}] ${l.transaction_date} D:${l.debit} C:${l.credit} ${(l.counterparty_name||'').slice(0,40)}`));
  }
})().catch(e => { console.error(e); process.exit(1); });
