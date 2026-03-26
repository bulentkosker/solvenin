/**
 * Load COA Templates into Supabase
 * Usage: node seeds/load_coa_templates.js
 *
 * Reads all coa_*.json files from the seeds/ directory
 * and upserts them into chart_of_accounts_templates table.
 */

const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = 'https://jaakjdzpdizjbzvbtcld.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

if (!SUPABASE_SERVICE_KEY) {
  console.error('Error: Set SUPABASE_SERVICE_KEY environment variable');
  console.error('Usage: SUPABASE_SERVICE_KEY=your_key node seeds/load_coa_templates.js');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

async function main() {
  const seedDir = path.join(__dirname);
  const files = fs.readdirSync(seedDir).filter(f => f.startsWith('coa_') && f.endsWith('.json'));

  if (files.length === 0) {
    console.log('No coa_*.json files found in seeds/');
    return;
  }

  let totalInserted = 0;
  let totalSkipped = 0;

  for (const file of files) {
    const filePath = path.join(seedDir, file);
    const raw = fs.readFileSync(filePath, 'utf8');
    let accounts;
    try {
      accounts = JSON.parse(raw);
    } catch (e) {
      console.error(`  ✗ ${file}: Invalid JSON — ${e.message}`);
      continue;
    }

    if (!Array.isArray(accounts) || accounts.length === 0) {
      console.warn(`  ⚠ ${file}: Empty or not an array, skipping`);
      continue;
    }

    const countryCode = accounts[0].country_code;
    console.log(`\n📄 ${file} — ${countryCode} (${accounts.length} accounts)`);

    // Batch upsert in chunks of 200
    const BATCH = 200;
    for (let i = 0; i < accounts.length; i += BATCH) {
      const chunk = accounts.slice(i, i + BATCH);
      const { data, error } = await sb
        .from('chart_of_accounts_templates')
        .upsert(chunk, { onConflict: 'country_code,account_code', ignoreDuplicates: true });

      if (error) {
        console.error(`  ✗ Batch ${Math.floor(i / BATCH) + 1} error:`, error.message);
      } else {
        totalInserted += chunk.length;
        process.stdout.write(`  ✓ ${Math.min(i + BATCH, accounts.length)}/${accounts.length}\r`);
      }
    }
    console.log(`  ✓ ${accounts.length} accounts loaded`);
  }

  console.log(`\n✅ Done. ${totalInserted} records processed from ${files.length} files.`);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
