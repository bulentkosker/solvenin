#!/usr/bin/env node
/** Generic SQL runner via exec_sql RPC. Usage: node scripts/run-sql.js <path-to-sql> */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');

const sqlPath = process.argv[2];
if (!sqlPath) { console.error('Usage: node scripts/run-sql.js <path>'); process.exit(1); }

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
const sql = fs.readFileSync(sqlPath, 'utf8');
console.log(`Running ${sqlPath} (${sql.length} bytes)…`);

(async () => {
  const { data, error } = await sb.rpc('exec_sql', { query: sql });
  if (error) { console.error('FAILED:', error.message); process.exit(1); }
  console.log('OK'); if (data) console.log(JSON.stringify(data));
})();
