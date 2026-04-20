#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { extractSheetsFromExcel } = require('./parsers/excel-parser');
const { parseWithTemplate } = require('./parsers/template-engine');

const SAMPLE = path.join(__dirname, 'samples', 'cashbook.xlsx');
const TEMPLATE = JSON.parse(fs.readFileSync(path.join(__dirname, 'templates', 'generic-cashbook.json'), 'utf8'));
const OUTPUT_PARSED = path.join(__dirname, 'samples', 'output-cashbook-parsed.json');

const rawData = extractSheetsFromExcel(SAMPLE);

console.log('Parsing with template:', TEMPLATE.name);
const result = parseWithTemplate(rawData, TEMPLATE);

fs.writeFileSync(OUTPUT_PARSED, JSON.stringify(result, null, 2), 'utf8');
console.log(`Output: ${OUTPUT_PARSED}`);

console.log('\n─── METADATA ───');
Object.entries(result.metadata).forEach(([k,v]) => console.log(`  ${k}: ${v}`));

console.log(`\n─── TRANSACTIONS: ${result.transactions.length} ───`);
const bySec = {};
let totalDebit = 0, totalCredit = 0;
result.transactions.forEach(tx => {
  totalDebit += tx.debit || 0;
  totalCredit += tx.credit || 0;
  bySec[tx.section] = (bySec[tx.section] || 0) + 1;
});
console.log(`  Total Debit:  ${totalDebit.toLocaleString()}`);
console.log(`  Total Credit: ${totalCredit.toLocaleString()}`);
Object.entries(bySec).forEach(([s,c]) => console.log(`  Section "${s}": ${c} transactions`));

console.log('\n─── FIRST 5 TRANSACTIONS ───');
result.transactions.slice(0, 5).forEach((tx, i) => {
  console.log(`  [${i+1}] ${tx.transaction_date} [${tx.section}] D:${tx.debit||0} C:${tx.credit||0} | ${(tx.description||'—').slice(0,50)}`);
});

if (result.warnings.length) {
  console.log(`\n─── WARNINGS (${result.warnings.length}) ───`);
  result.warnings.slice(0, 5).forEach(w => console.log(`  ⚠ ${w}`));
}
