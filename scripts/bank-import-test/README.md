# Bank Import Test Scripts

Bank statement parser test altyapısı. UI'ya geçmeden önce parser mantığını doğrulamak için.

## Yapı

```
parsers/
  pdf-parser.js        — pdfjs-dist wrapper (text + positions)
  excel-parser.js      — SheetJS wrapper (rows + cells + merges)
  template-engine.js   — (henüz yok) template JSON → parsed transactions

templates/             — (henüz yok) parser template JSON'ları
samples/               — test dosyaları (git'e eklenmez)

test-halyk.js          — Halyk Bank PDF raw extract
test-bcc.js            — BCC Bank PDF raw extract
test-cashbook.js       — Kasa defteri Excel raw extract
```

## Çalıştırma

```bash
cd scripts/bank-import-test
node test-halyk.js      # → samples/output-halyk.txt
node test-bcc.js        # → samples/output-bcc.txt
node test-cashbook.js   # → samples/output-cashbook.txt
```

## Bağımlılıklar

Proje root'tan: `npm install pdfjs-dist xlsx`
