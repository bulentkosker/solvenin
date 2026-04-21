#!/usr/bin/env node
/** Apply 064 migration directly via JS client (exec_sql can't run BEGIN/COMMIT). */
require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });

(async () => {
  const { data: rows } = await sb.from('import_templates')
    .select('id, name, detection_rules')
    .eq('is_system', true);

  let updated = 0;
  for (const r of rows) {
    const rules = r.detection_rules || {};
    if (rules.bank_identifier && !rules.bank_identifier_pattern) {
      const newRules = { ...rules, bank_identifier_pattern: rules.bank_identifier };
      delete newRules.bank_identifier;
      const { error } = await sb.from('import_templates').update({ detection_rules: newRules }).eq('id', r.id);
      if (error) { console.error(`FAIL ${r.name}: ${error.message}`); continue; }
      console.log(`✓ ${r.name}: ${JSON.stringify(newRules)}`);
      updated++;
    } else {
      console.log(`  skip ${r.name} (already migrated or no bank_identifier)`);
    }
  }

  // Log migration
  await sb.from('migrations_log').upsert({
    file_name: '064_detection_rules_rename.sql',
    notes: `Rename detection_rules.bank_identifier → bank_identifier_pattern (${updated} rows)`
  }, { onConflict: 'file_name' });

  console.log(`\nDone. ${updated} rows updated.`);
})().catch(e => { console.error(e); process.exit(1); });
