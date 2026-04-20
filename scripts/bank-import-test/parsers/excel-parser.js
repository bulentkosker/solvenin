/**
 * Excel Extractor — SheetJS (xlsx) wrapper
 * Extracts all sheets with rows, cell positions, and merge info.
 */
const XLSX = require('xlsx');
const path = require('path');

function extractSheetsFromExcel(filePath) {
  const wb = XLSX.readFile(filePath, { cellStyles: true, cellDates: true });

  const sheets = wb.SheetNames.map(sheetName => {
    const ws = wb.Sheets[sheetName];
    const range = XLSX.utils.decode_range(ws['!ref'] || 'A1');

    // Row-based extraction
    const rows = [];
    for (let r = range.s.r; r <= range.e.r; r++) {
      const row = [];
      for (let c = range.s.c; c <= range.e.c; c++) {
        const addr = XLSX.utils.encode_cell({ r, c });
        const cell = ws[addr];
        row.push(cell ? (cell.v !== undefined ? cell.v : '') : '');
      }
      rows.push(row);
    }

    // Cell map (A1 → value)
    const cellMap = {};
    for (let r = range.s.r; r <= range.e.r; r++) {
      for (let c = range.s.c; c <= range.e.c; c++) {
        const addr = XLSX.utils.encode_cell({ r, c });
        const cell = ws[addr];
        if (cell && cell.v !== undefined) cellMap[addr] = cell.v;
      }
    }

    // Merged cells
    const merges = (ws['!merges'] || []).map(m => ({
      range: XLSX.utils.encode_range(m),
      start: XLSX.utils.encode_cell(m.s),
      end: XLSX.utils.encode_cell(m.e),
      rows: m.e.r - m.s.r + 1,
      cols: m.e.c - m.s.c + 1,
    }));

    // Column widths
    const colWidths = (ws['!cols'] || []).map((c, i) => ({
      col: XLSX.utils.encode_col(i),
      width: c?.wch || c?.wpx || null,
    })).filter(c => c.width);

    return {
      sheetName,
      rows,
      cellMap,
      merges,
      colWidths,
      totalRows: rows.length,
      totalCols: range.e.c - range.s.c + 1,
    };
  });

  return {
    sheets,
    fileName: path.basename(filePath),
    sheetCount: wb.SheetNames.length,
  };
}

module.exports = { extractSheetsFromExcel };
