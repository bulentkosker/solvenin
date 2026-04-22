#!/usr/bin/env node
/**
 * Verification: create a throwaway company, run the exact template-load
 * logic used by accounting.html (upsert on company_id+code with
 * deleted_at cleared), confirm 211 rows land, then delete the company.
 */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

(async () => {
  let testCompanyId = null;
  try {
    // Pick any real user as owner (RLS-friendly if we swap to user client; service key bypasses anyway)
    const { data: owner } = await sb.from('profiles').select('id').limit(1).single();
    if (!owner) throw new Error('No user in profiles');

    // Create test company
    const { data: comp, error: cErr } = await sb.from('companies').insert({
      name: '__TR_TEMPLATE_TEST__',
      slug: '__tr-template-test-' + Date.now(),
      country_code: 'TR',
      base_currency: 'TRY',
      status: 'active',
      owner_id: owner.id
    }).select('id').single();
    if (cErr) throw cErr;
    testCompanyId = comp.id;
    console.log('Created test company:', testCompanyId);

    // Load TR template exactly like accounting.html:731 does
    const { data: templates, error: tErr } = await sb.from('chart_of_accounts_templates')
      .select('account_code, account_name_local, account_name_en, account_type, parent_code, level')
      .eq('country_code', 'TR');
    if (tErr) throw tErr;
    console.log('Template rows fetched:', templates.length);

    const BATCH = 200;
    for (let i = 0; i < templates.length; i += BATCH) {
      const { error } = await sb.from('chart_of_accounts').upsert(
        templates.slice(i, i + BATCH).map(t => ({
          company_id: testCompanyId, code: t.account_code,
          name: t.account_name_en, name_local: t.account_name_local,
          type: t.account_type, parent_code: t.parent_code,
          level: t.level, country_code: 'TR', is_system: false, is_active: true,
          deleted_at: null, deleted_by: null
        })),
        { onConflict: 'company_id,code' }
      );
      if (error) throw error;
    }

    // Verify
    const { count } = await sb.from('chart_of_accounts').select('id', { count: 'exact', head: true }).eq('company_id', testCompanyId);
    const { data: rows } = await sb.from('chart_of_accounts').select('type').eq('company_id', testCompanyId);
    const byType = {};
    rows.forEach(r => { byType[r.type] = (byType[r.type] || 0) + 1; });
    console.log('Loaded into test company:', count, 'rows');
    console.log('By type:', byType);

    // Sample spot-checks
    const { data: samples } = await sb.from('chart_of_accounts').select('code, name, name_local, type')
      .eq('company_id', testCompanyId)
      .in('code', ['100', '391', '500', '632', '690', '770'])
      .order('code');
    console.log('\nSample accounts (TR/EN):');
    samples.forEach(s => console.log(`  ${s.code.padEnd(4)} ${s.type.padEnd(10)} ${s.name_local.padEnd(35)} | ${s.name}`));

    const ok = count === 211;
    console.log('\n' + (ok ? '✓ PASS' : '✗ FAIL') + ' — expected 211 rows, got ' + count);
    process.exitCode = ok ? 0 : 1;
  } catch (e) {
    console.error('ERROR:', e.message);
    process.exitCode = 1;
  } finally {
    if (testCompanyId) {
      await sb.from('chart_of_accounts').delete().eq('company_id', testCompanyId);
      await sb.from('companies').delete().eq('id', testCompanyId);
      console.log('\nTest company cleaned up.');
    }
  }
})();
