#!/usr/bin/env node
/**
 * Cashbook Excel — raw extraction test
 * Output: samples/output-cashbook.txt
 */
const fs = require('fs');
const path = require('path');
const { extractSheetsFromExcel } = require('./parsers/excel-parser');

const SAMPLE = path.join(__dirname, 'samples', 'cashbook.xlsx');
const OUTPUT = path.join(__dirname, 'samples', 'output-cashbook.txt');

const result = extractSheetsFromExcel(SAMPLE);

const lines = [];
lines.push('═══════════════════════════════════════════════════');
lines.push('CASHBOOK EXCEL — RAW EXTRACTION');
lines.push('═══════════════════════════════════════════════════');
lines.push(`File: ${result.fileName}`);
lines.push(`Sheets: ${result.sheetCount}`);
lines.push('');

for (const sheet of result.sheets) {
  lines.push(`─── SHEET: "${sheet.sheetName}" (${sheet.totalRows} rows × ${sheet.totalCols} cols) ───`);
  lines.push('');

  // First 30 rows as table
  lines.push('▸ ROWS (first 30):');
  const maxCols = Math.min(sheet.totalCols, 15); // cap at 15 cols
  const displayRows = sheet.rows.slice(0, 30);

  // Calculate column widths
  const colWidths = Array(maxCols).fill(4);
  displayRows.forEach(row => {
    row.slice(0, maxCols).forEach((cell, ci) => {
      const len = String(cell ?? '').slice(0, 30).length;
      colWidths[ci] = Math.max(colWidths[ci], len);
    });
  });

  // Header line (column letters)
  const colLetters = Array.from({ length: maxCols }, (_, i) => String.fromCharCode(65 + i));
  lines.push('  ROW | ' + colLetters.map((l, i) => l.padEnd(colWidths[i])).join(' | '));
  lines.push('  ' + '─'.repeat(6 + colWidths.reduce((s, w) => s + w + 3, 0)));

  displayRows.forEach((row, ri) => {
    const cells = row.slice(0, maxCols).map((cell, ci) => {
      let val = cell ?? '';
      if (val instanceof Date) val = val.toISOString().split('T')[0];
      return String(val).slice(0, 30).padEnd(colWidths[ci]);
    });
    lines.push(`  ${String(ri + 1).padStart(3)} | ${cells.join(' | ')}`);
  });
  lines.push('');

  // Merged cells
  if (sheet.merges.length) {
    lines.push(`▸ MERGED CELLS (${sheet.merges.length}):`);
    sheet.merges.slice(0, 20).forEach(m => {
      lines.push(`  ${m.range} (${m.rows}r × ${m.cols}c)`);
    });
    lines.push('');
  }

  // Cell map sample (first 50 non-empty cells)
  const nonEmpty = Object.entries(sheet.cellMap).slice(0, 50);
  lines.push(`▸ CELL MAP (first 50 non-empty):`);
  nonEmpty.forEach(([addr, val]) => {
    let display = val;
    if (display instanceof Date) display = display.toISOString().split('T')[0];
    lines.push(`  ${addr.padEnd(6)} = ${String(display).slice(0, 60)}`);
  });
  lines.push('');
}

fs.writeFileSync(OUTPUT, lines.join('\n'), 'utf8');
console.log(`Output: ${OUTPUT} (${lines.length} lines)`);

console.log(`\nSheets: ${result.sheetCount}`);
result.sheets.forEach(s => console.log(`  "${s.sheetName}": ${s.totalRows} rows × ${s.totalCols} cols, ${s.merges.length} merges`));
