#!/usr/bin/env node
/**
 * BCC Bank PDF — raw text extraction test
 * Output: samples/output-bcc.txt
 */
const fs = require('fs');
const path = require('path');
const { extractTextFromPdf } = require('./parsers/pdf-parser');

const SAMPLE = path.join(__dirname, 'samples', 'bcc.pdf');
const OUTPUT = path.join(__dirname, 'samples', 'output-bcc.txt');

(async () => {
  console.log('Extracting:', SAMPLE);
  const { pages, metadata } = await extractTextFromPdf(SAMPLE);

  const lines = [];
  lines.push('═══════════════════════════════════════════════════');
  lines.push('BCC BANK PDF — RAW EXTRACTION');
  lines.push('═══════════════════════════════════════════════════');
  lines.push(`File: ${metadata.fileName}`);
  lines.push(`Size: ${(metadata.fileSize / 1024).toFixed(1)} KB`);
  lines.push(`Pages: ${metadata.numPages}`);
  lines.push('');

  for (const page of pages) {
    lines.push(`─── PAGE ${page.pageNumber} (${page.width}x${page.height}) ───`);
    lines.push('');

    lines.push('▸ PLAIN TEXT:');
    lines.push(page.text.slice(0, 3000));
    lines.push('');

    lines.push('▸ TEXT ITEMS (first 40 — x, y, text):');
    page.textItems.slice(0, 40).forEach((ti, i) => {
      lines.push(`  [${String(i).padStart(2)}] x=${String(ti.x).padStart(6)} y=${String(ti.y).padStart(6)} w=${String(ti.width).padStart(5)} | "${ti.text}"`);
    });
    lines.push('');

    const xBuckets = {};
    page.textItems.forEach(ti => {
      const xKey = Math.round(ti.x / 5) * 5;
      xBuckets[xKey] = (xBuckets[xKey] || 0) + 1;
    });
    const topX = Object.entries(xBuckets).sort((a, b) => b[1] - a[1]).slice(0, 10);
    lines.push('▸ X-COORDINATE CLUSTERS (column detection):');
    topX.forEach(([x, count]) => lines.push(`  x≈${x}: ${count} items`));
    lines.push('');
  }

  fs.writeFileSync(OUTPUT, lines.join('\n'), 'utf8');
  console.log(`Output: ${OUTPUT} (${lines.length} lines)`);

  console.log(`\nPages: ${metadata.numPages}, File: ${(metadata.fileSize/1024).toFixed(0)}KB`);
  pages.forEach(p => console.log(`  Page ${p.pageNumber}: ${p.textItems.length} text items, ${p.text.split('\n').length} lines`));
})().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
