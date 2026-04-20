/**
 * PDF Text Extractor — pdfjs-dist wrapper
 * Extracts text + position data from each page.
 */
const fs = require('fs');
const path = require('path');

async function extractTextFromPdf(filePath) {
  // pdfjs-dist legacy build for Node.js (no canvas needed for text-only)
  const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js');

  const data = new Uint8Array(fs.readFileSync(filePath));
  const doc = await pdfjsLib.getDocument({ data, useSystemFonts: true }).promise;

  const pages = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    const viewport = page.getViewport({ scale: 1.0 });

    const textItems = content.items.map(item => ({
      text: item.str,
      x: Math.round(item.transform[4] * 100) / 100,
      y: Math.round((viewport.height - item.transform[5]) * 100) / 100, // flip Y
      width: Math.round(item.width * 100) / 100,
      height: Math.round(item.height * 100) / 100,
    }));

    // Build plain text by grouping items on same Y line
    const lines = {};
    textItems.forEach(ti => {
      const yKey = Math.round(ti.y); // round to nearest pixel
      if (!lines[yKey]) lines[yKey] = [];
      lines[yKey].push(ti);
    });
    const sortedLines = Object.keys(lines).sort((a, b) => a - b);
    const plainText = sortedLines.map(y => {
      return lines[y].sort((a, b) => a.x - b.x).map(t => t.text).join(' ');
    }).join('\n');

    pages.push({
      pageNumber: i,
      text: plainText,
      textItems,
      width: viewport.width,
      height: viewport.height,
    });
  }

  const metadata = {
    numPages: doc.numPages,
    fileName: path.basename(filePath),
    fileSize: fs.statSync(filePath).size,
  };

  return { pages, metadata };
}

module.exports = { extractTextFromPdf };
