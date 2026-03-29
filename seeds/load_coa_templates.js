require('dotenv').config();
/**
 * Load COA Templates into Supabase
 *
 * Usage:
 *   node seeds/load_coa_templates.js
 *
 *   # Also load templates into a specific company's chart_of_accounts
 *   SUPABASE_SERVICE_KEY=your_key node seeds/load_coa_templates.js --load-company COMPANY_ID --country TR
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

// Parse CLI args
const args = process.argv.slice(2);
const companyIdx = args.indexOf('--load-company');
const countryIdx = args.indexOf('--country');
const targetCompanyId = companyIdx !== -1 ? args[companyIdx + 1] : null;
const targetCountry = countryIdx !== -1 ? args[countryIdx + 1] : null;

async function loadTemplates() {
  const seedDir = path.join(__dirname);
  const files = fs.readdirSync(seedDir).filter(f => f.startsWith('coa_') && f.endsWith('.json'));

  if (files.length === 0) {
    console.log('No coa_*.json files found in seeds/');
    return;
  }

  let totalInserted = 0;

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

    const BATCH = 200;
    for (let i = 0; i < accounts.length; i += BATCH) {
      const chunk = accounts.slice(i, i + BATCH);
      const { error } = await sb
        .from('chart_of_accounts_templates')
        .upsert(chunk, { onConflict: 'country_code,account_code', ignoreDuplicates: true });

      if (error) {
        console.error(`  ✗ Batch ${Math.floor(i / BATCH) + 1} error:`, error.message);
      } else {
        totalInserted += chunk.length;
      }
    }
    console.log(`  ✓ ${accounts.length} accounts loaded`);
  }

  console.log(`\n✅ Templates done. ${totalInserted} records processed from ${files.length} files.`);
}

async function loadCompanyCoa(companyId, countryCode) {
  console.log(`\n🏢 Loading COA for company ${companyId}, country ${countryCode}`);

  // Fetch templates
  const { data: templates, error: tErr } = await sb.from('chart_of_accounts_templates')
    .select('account_code, account_name_local, account_name_en, account_type, parent_code, level')
    .eq('country_code', countryCode);

  if (tErr) { console.error('  ✗ Template fetch error:', tErr.message); return; }
  if (!templates || !templates.length) {
    console.error(`  ✗ No templates found for country: ${countryCode}`);
    return;
  }

  console.log(`  Found ${templates.length} template accounts`);

  // Map to chart_of_accounts columns: code, name, name_local, type
  const BATCH = 200;
  let inserted = 0;
  for (let i = 0; i < templates.length; i += BATCH) {
    const rows = templates.slice(i, i + BATCH).map(t => ({
      company_id: companyId,
      code: t.account_code,
      name: t.account_name_en,
      name_local: t.account_name_local,
      type: t.account_type,
      parent_code: t.parent_code,
      level: t.level,
      country_code: countryCode,
      is_system: true,
      is_active: true
    }));

    const { error } = await sb.from('chart_of_accounts')
      .upsert(rows, { onConflict: 'company_id,code' });

    if (error) {
      console.error(`  ✗ Batch ${Math.floor(i / BATCH) + 1} error:`, error.message);
    } else {
      inserted += rows.length;
    }
  }

  console.log(`  ✅ ${inserted}/${templates.length} accounts loaded into chart_of_accounts`);
}

async function main() {
  // Always load templates first
  await loadTemplates();

  // If --load-company flag is set, also load into company's chart_of_accounts
  if (targetCompanyId && targetCountry) {
    await loadCompanyCoa(targetCompanyId, targetCountry);
  } else if (targetCompanyId && !targetCountry) {
    // Try to get country from company record
    const { data: comp } = await sb.from('companies')
      .select('country_code').eq('id', targetCompanyId).single();
    if (comp?.country_code) {
      await loadCompanyCoa(targetCompanyId, comp.country_code);
    } else {
      console.error('  ✗ No country_code found for company. Use --country flag.');
    }
  }
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
