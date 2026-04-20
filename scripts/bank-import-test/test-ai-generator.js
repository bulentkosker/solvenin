#!/usr/bin/env node
/**
 * AI Template Generator Test
 * Usage: node test-ai-generator.js halyk.pdf
 *        node test-ai-generator.js bcc.pdf
 *        node test-ai-generator.js cashbook.xlsx
 */
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });

const { extractTextFromPdf } = require('./parsers/pdf-parser');
const { extractSheetsFromExcel } = require('./parsers/excel-parser');
const { parseWithTemplate } = require('./parsers/template-engine');
const { generateTemplate } = require('./ai-generator');

const FILE_ARG = process.argv[2];
if (!FILE_ARG) { console.error('Usage: node test-ai-generator.js <halyk.pdf|bcc.pdf|cashbook.xlsx>'); process.exit(1); }

const SAMPLE_PATH = path.join(__dirname, 'samples', FILE_ARG);
if (!fs.existsSync(SAMPLE_PATH)) { console.error('File not found:', SAMPLE_PATH); process.exit(1); }

const isPdf = FILE_ARG.endsWith('.pdf');
const format = isPdf ? 'pdf' : 'xlsx';

// Manual template for comparison
const MANUAL_TEMPLATES = {
  'halyk.pdf': 'halyk-kz-pdf.json',
  'bcc.pdf': 'bcc-kz-pdf.json',
  'cashbook.xlsx': 'generic-cashbook.json',
};

// API key
const API_KEY = process.env.ANTHROPIC_API_KEY || (() => {
  // Try reading from .env or Supabase
  try {
    const { createClient } = require('@supabase/supabase-js');
    // Will be loaded async below
    return null;
  } catch (e) { return null; }
})();

async function getApiKey() {
  if (API_KEY) return API_KEY;
  // Fallback: read from Supabase app_settings
  try {
    const { createClient } = require('@supabase/supabase-js');
    const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
    const { data } = await sb.from('app_settings').select('value').eq('key', 'anthropic_api_key').single();
    return data?.value;
  } catch (e) { return null; }
}

(async () => {
  const apiKey = await getApiKey();
  if (!apiKey) { console.error('ANTHROPIC_API_KEY not found in .env or app_settings'); process.exit(1); }

  // 1. Extract
  console.log(`\n📄 Extracting: ${FILE_ARG}`);
  let rawData;
  if (isPdf) rawData = await extractTextFromPdf(SAMPLE_PATH);
  else rawData = extractSheetsFromExcel(SAMPLE_PATH);

  // 2. Generate AI template
  console.log('🤖 Generating template with Claude...');
  const t0 = Date.now();
  const fileInfo = { filename: FILE_ARG, format, size: fs.statSync(SAMPLE_PATH).size, target_module: format === 'xlsx' ? 'cash_register' : 'bank_statement' };

  let aiResult;
  try {
    aiResult = await generateTemplate(rawData, fileInfo, apiKey);
  } catch (e) {
    console.error('❌ AI generation failed:', e.message);
    process.exit(1);
  }
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);

  // Save AI template
  const aiTemplatePath = path.join(__dirname, 'templates', 'ai-generated', FILE_ARG.replace(/\.[^.]+$/, '') + '-ai.json');
  fs.writeFileSync(aiTemplatePath, JSON.stringify(aiResult.template, null, 2), 'utf8');
  console.log(`✅ AI template saved: ${aiTemplatePath}`);
  console.log(`   Time: ${elapsed}s, Attempts: ${aiResult.attempts}, Confidence: ${aiResult.confidence}`);
  console.log(`   Tokens: input=${aiResult.tokens_used.input_tokens}, output=${aiResult.tokens_used.output_tokens}`);

  // Show AI analysis
  if (aiResult.analysis) {
    console.log('\n─── AI ANALİZ ───');
    console.log(aiResult.analysis.slice(0, 600));
    if (aiResult.analysis.length > 600) console.log('... (truncated)');
  }

  if (aiResult.validation.errors.length) console.log(`   ❌ Errors: ${aiResult.validation.errors.join(', ')}`);
  if (aiResult.validation.warnings.length) console.log(`   ⚠ Warnings: ${aiResult.validation.warnings.join(', ')}`);

  // 3. Parse with AI template
  console.log('\n📊 Parsing with AI template...');
  let aiParsed;
  try {
    aiParsed = parseWithTemplate(rawData, aiResult.template);
  } catch (e) {
    console.error('❌ AI template parse failed:', e.message);
    aiParsed = { metadata: {}, transactions: [], warnings: [e.message] };
  }

  const aiDebit = aiParsed.transactions.reduce((s, t) => s + (t.debit || 0), 0);
  const aiCredit = aiParsed.transactions.reduce((s, t) => s + (t.credit || 0), 0);

  console.log(`   Transactions: ${aiParsed.transactions.length}`);
  console.log(`   Total Debit:  ${aiDebit.toLocaleString()}`);
  console.log(`   Total Credit: ${aiCredit.toLocaleString()}`);
  console.log(`   Metadata:`, JSON.stringify(aiParsed.metadata));
  if (aiParsed.warnings.length) console.log(`   Warnings: ${aiParsed.warnings.slice(0, 3).join('; ')}`);

  // 4. Compare with manual template (if exists)
  const manualFile = MANUAL_TEMPLATES[FILE_ARG];
  if (manualFile) {
    const manualTemplatePath = path.join(__dirname, 'templates', manualFile);
    const manualTemplate = JSON.parse(fs.readFileSync(manualTemplatePath, 'utf8'));
    const manualParsed = parseWithTemplate(rawData, manualTemplate);
    const manualDebit = manualParsed.transactions.reduce((s, t) => s + (t.debit || 0), 0);
    const manualCredit = manualParsed.transactions.reduce((s, t) => s + (t.credit || 0), 0);

    console.log('\n═══ COMPARISON: AI vs Manual ═══');
    const cmp = (label, ai, manual) => {
      const match = ai === manual || (typeof ai === 'number' && typeof manual === 'number' && Math.abs(ai - manual) < 0.02);
      console.log(`  ${match ? '✅' : '❌'} ${label.padEnd(20)} AI: ${ai}  Manual: ${manual}`);
      return match;
    };

    let score = 0, total = 0;
    total++; if (cmp('Transactions', aiParsed.transactions.length, manualParsed.transactions.length)) score++;
    total++; if (cmp('Total Debit', Math.round(aiDebit * 100) / 100, Math.round(manualDebit * 100) / 100)) score++;
    total++; if (cmp('Total Credit', Math.round(aiCredit * 100) / 100, Math.round(manualCredit * 100) / 100)) score++;

    // Metadata comparison
    for (const key of Object.keys(manualParsed.metadata)) {
      const aiVal = aiParsed.metadata[key];
      const manVal = manualParsed.metadata[key];
      if (manVal != null) {
        total++;
        if (cmp('meta.' + key, aiVal, manVal)) score++;
      }
    }

    const pct = Math.round(score / total * 100);
    console.log(`\n🎯 Score: ${score}/${total} (${pct}%)`);
    console.log(pct >= 80 ? '✅ AI template GOOD' : pct >= 50 ? '⚠ AI template NEEDS TUNING' : '❌ AI template POOR');
  }
})().catch(e => { console.error('FATAL:', e); process.exit(1); });
