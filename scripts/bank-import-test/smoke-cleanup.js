#!/usr/bin/env node
/** Cleanup leftover smoke-test data_imports + polluted AI templates. */
require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const { createClient } = require('@supabase/supabase-js');
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });

(async () => {
  const COMPANY_ID = '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82';

  const fileNames = ['halyk.pdf', 'cashbook.xlsx', 'bcc.pdf'];
  const { data: imports } = await sb.from('data_imports')
    .select('id, file_name, created_at').eq('company_id', COMPANY_ID).in('file_name', fileNames).order('created_at', { ascending: false });
  console.log(`Found ${imports?.length || 0} smoke test data_imports`);

  if (imports?.length) {
    for (const imp of imports) {
      await sb.from('data_import_lines').delete().eq('import_id', imp.id);
      await sb.from('data_imports').delete().eq('id', imp.id);
    }
    console.log('Deleted test data_imports + lines');
  }

  const { data: aiTpl } = await sb.from('import_templates').select('id, name').eq('company_id', COMPANY_ID).eq('is_ai_generated', true);
  console.log(`AI templates: ${aiTpl?.length || 0}`);
  if (aiTpl?.length) {
    for (const t of aiTpl) {
      await sb.from('import_templates').delete().eq('id', t.id);
    }
    console.log('Deleted AI templates');
  }

  console.log('Cleanup done.');
})().catch(e => { console.error(e); process.exit(1); });
