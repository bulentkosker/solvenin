/**
 * Excel Extractor — Browser version (SheetJS XLSX global)
 * Requires: <script src="https://cdn.sheetjs.com/xlsx-0.20.1/package/dist/xlsx.full.min.js"></script>
 */
window.BankImportExcelParser = {

  extractSheetsFromExcel(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const wb = XLSX.read(e.target.result, { type: 'array', cellStyles: true, cellDates: true });
          const sheets = wb.SheetNames.map(sheetName => {
            const ws = wb.Sheets[sheetName];
            const range = XLSX.utils.decode_range(ws['!ref'] || 'A1');
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
            const cellMap = {};
            for (let r = range.s.r; r <= range.e.r; r++) {
              for (let c = range.s.c; c <= range.e.c; c++) {
                const addr = XLSX.utils.encode_cell({ r, c });
                const cell = ws[addr];
                if (cell && cell.v !== undefined) cellMap[addr] = cell.v;
              }
            }
            const merges = (ws['!merges'] || []).map(m => ({
              range: XLSX.utils.encode_range(m),
              start: XLSX.utils.encode_cell(m.s),
              end: XLSX.utils.encode_cell(m.e),
            }));
            return { sheetName, rows, cellMap, merges, totalRows: rows.length, totalCols: range.e.c - range.s.c + 1 };
          });
          resolve({ sheets, fileName: file.name, sheetCount: wb.SheetNames.length });
        } catch (err) { reject(err); }
      };
      reader.onerror = () => reject(new Error('File read error'));
      reader.readAsArrayBuffer(file);
    });
  }
};
