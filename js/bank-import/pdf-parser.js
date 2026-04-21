/**
 * PDF Text Extractor — Browser version (pdfjs-dist global)
 * Requires: <script src="https://unpkg.com/pdfjs-dist@4.0.379/build/pdf.min.mjs" type="module"></script>
 * or legacy: pdfjsLib global
 */
window.BankImportPdfParser = {

  async extractTextFromPdf(file) {
    const pdfjsLib = window.pdfjsLib;
    if (!pdfjsLib) throw new Error('pdfjs-dist not loaded');

    const arrayBuffer = await file.arrayBuffer();
    const data = new Uint8Array(arrayBuffer);
    const doc = await pdfjsLib.getDocument({ data }).promise;

    const pages = [];
    for (let i = 1; i <= doc.numPages; i++) {
      const page = await doc.getPage(i);
      const content = await page.getTextContent();
      const viewport = page.getViewport({ scale: 1.0 });

      const textItems = content.items.map(item => ({
        text: item.str,
        x: Math.round(item.transform[4] * 100) / 100,
        y: Math.round((viewport.height - item.transform[5]) * 100) / 100,
        width: Math.round(item.width * 100) / 100,
        height: Math.round(item.height * 100) / 100,
      }));

      const lines = {};
      textItems.forEach(ti => {
        const yKey = Math.round(ti.y);
        if (!lines[yKey]) lines[yKey] = [];
        lines[yKey].push(ti);
      });
      const sortedLines = Object.keys(lines).sort((a, b) => a - b);
      const plainText = sortedLines.map(y =>
        lines[y].sort((a, b) => a.x - b.x).map(t => t.text).join(' ')
      ).join('\n');

      pages.push({ pageNumber: i, text: plainText, textItems, width: viewport.width, height: viewport.height });
    }

    return {
      pages,
      metadata: { numPages: doc.numPages, fileName: file.name, fileSize: file.size }
    };
  }
};
