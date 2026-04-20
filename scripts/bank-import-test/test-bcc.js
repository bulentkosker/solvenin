#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { extractTextFromPdf } = require('./parsers/pdf-parser');
const { parseWithTemplate } = require('./parsers/template-engine');

const SAMPLE = path.join(__dirname, 'samples', 'bcc.pdf');
const TEMPLATE = JSON.parse(fs.readFileSync(path.join(__dirname, 'templates', 'bcc-kz-pdf.json'), 'utf8'));
const OUTPUT_PARSED = path.join(__dirname, 'samples', 'output-bcc-parsed.json');

(async () => {
  console.log('Extracting:', SAMPLE);
  const rawData = await extractTextFromPdf(SAMPLE);

  console.log('\nParsing with template:', TEMPLATE.name);
  const result = parseWithTemplate(rawData, TEMPLATE);

  fs.writeFileSync(OUTPUT_PARSED, JSON.stringify(result, null, 2), 'utf8');
  console.log(`Output: ${OUTPUT_PARSED}`);

  console.log('\n─── METADATA ───');
  Object.entries(result.metadata).forEach(([k,v]) => console.log(`  ${k}: ${v}`));

  console.log(`\n─── TRANSACTIONS: ${result.transactions.length} ───`);
  let totalDebit = 0, totalCredit = 0;
  result.transactions.forEach(tx => { totalDebit += tx.debit || 0; totalCredit += tx.credit || 0; });
  console.log(`  Total Debit:  ${totalDebit.toLocaleString()}`);
  console.log(`  Total Credit: ${totalCredit.toLocaleString()}`);

  console.log('\n─── FIRST 3 TRANSACTIONS ───');
  result.transactions.slice(0, 3).forEach((tx, i) => {
    console.log(`  [${i+1}] ${tx.transaction_date} | D:${tx.debit||0} C:${tx.credit||0} | KNP:${tx.knp_code||'—'} | ${(tx.counterparty_name||'—').slice(0,40)}`);
  });

  if (result.warnings.length) {
    console.log(`\n─── WARNINGS (${result.warnings.length}) ───`);
    result.warnings.slice(0, 5).forEach(w => console.log(`  ⚠ ${w}`));
  }
})().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
