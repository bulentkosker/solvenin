#!/usr/bin/env node
/**
 * Generates seeds/068_turkey_coa_parkgroup_rebuild.sql from the official
 * Tekdüzen Hesap Planı structure. Scoped to PARK GROUP only.
 *
 * Data shape: sections → groups → accounts, each with (code, label, type).
 * parent_code wires the hierarchy; parent_id is resolved by the SQL at
 * the end via a join on (company_id, code).
 */

const fs = require('fs');
const path = require('path');

// ─── Data ─────────────────────────────────────────────────────────────

// Each section: { code, name, type, groups: [{ code, name, type, accounts: [...]}] }
// "type" of section cascades to children unless overridden per account.
const TREE = [
  {
    code: '1', name: 'Dönen Varlıklar', type: 'asset',
    groups: [
      { code: '10', name: 'Hazır Değerler', accounts: [
        ['100', 'Kasa'],
        ['101', 'Alınan Çekler'],
        ['102', 'Bankalar'],
        ['103', 'Verilen Çekler ve Ödeme Emirleri (-)'],
        ['108', 'Diğer Hazır Değerler'],
      ]},
      { code: '12', name: 'Ticari Alacaklar', accounts: [
        ['120', 'Alıcılar'],
        ['121', 'Alacak Senetleri'],
        ['127', 'Diğer Ticari Alacaklar'],
        ['128', 'Şüpheli Ticari Alacaklar'],
        ['129', 'Şüpheli Alacaklar Karşılığı (-)'],
      ]},
      { code: '13', name: 'Diğer Alacaklar', accounts: [
        ['131', 'Ortaklardan Alacaklar'],
        ['132', 'İştiraklerden Alacaklar'],
        ['133', 'Bağlı Ortaklıklardan Alacaklar'],
        ['135', 'Personelden Alacaklar'],
        ['136', 'Diğer Çeşitli Alacaklar'],
      ]},
      { code: '15', name: 'Stoklar', accounts: [
        ['150', 'İlk Madde ve Malzeme'],
        ['151', 'Yarı Mamuller'],
        ['152', 'Mamuller'],
        ['153', 'Ticari Mallar'],
        ['157', 'Diğer Stoklar'],
        ['158', 'Stok Değer Düşüklüğü Karşılığı (-)'],
      ]},
      { code: '19', name: 'Diğer Dönen Varlıklar', accounts: [
        ['190', 'Devreden KDV'],
        ['191', 'İndirilecek KDV'],
        ['192', 'Diğer KDV'],
        ['195', 'İş Avansları'],
        ['196', 'Personel Avansları'],
        ['197', 'Sayım ve Tesellüm Noksanları'],
        ['199', 'Diğer Çeşitli Dönen Varlıklar'],
      ]},
    ],
  },
  {
    code: '2', name: 'Duran Varlıklar', type: 'asset',
    groups: [
      { code: '22', name: 'Ticari Alacaklar', accounts: [
        ['220', 'Alıcılar'],
        ['221', 'Alacak Senetleri'],
      ]},
      { code: '25', name: 'Maddi Duran Varlıklar', accounts: [
        ['250', 'Arazi ve Arsalar'],
        ['251', 'Yeraltı ve Yerüstü Düzenleri'],
        ['252', 'Binalar'],
        ['253', 'Tesis, Makine ve Cihazlar'],
        ['254', 'Taşıtlar'],
        ['255', 'Demirbaşlar'],
        ['256', 'Diğer Maddi Duran Varlıklar'],
        ['257', 'Birikmiş Amortismanlar (-)'],
        ['258', 'Yapılmakta Olan Yatırımlar'],
        ['259', 'Verilen Avanslar'],
      ]},
      { code: '26', name: 'Maddi Olmayan Duran Varlıklar', accounts: [
        ['260', 'Haklar'],
        ['261', 'Şerefiye'],
        ['262', 'Kuruluş ve Örgütlenme Giderleri'],
        ['263', 'Araştırma ve Geliştirme Giderleri'],
        ['264', 'Özel Maliyetler'],
        ['267', 'Diğer Maddi Olmayan Duran Varlıklar'],
        ['268', 'Birikmiş Amortismanlar (-)'],
      ]},
    ],
  },
  {
    code: '3', name: 'Kısa Vadeli Yabancı Kaynaklar', type: 'liability',
    groups: [
      { code: '30', name: 'Mali Borçlar', accounts: [
        ['300', 'Banka Kredileri'],
        ['303', 'Uzun Vadeli Kredilerin Anapara Taksitleri'],
        ['304', 'Tahvil Anapara Borç Taksit ve Faizleri'],
        ['308', 'Menkul Kıymetler İhraç Farkı'],
      ]},
      { code: '32', name: 'Ticari Borçlar', accounts: [
        ['320', 'Satıcılar'],
        ['321', 'Borç Senetleri'],
        ['322', 'Borç Senetleri Reeskontu (-)'],
        ['326', 'Alınan Depozito ve Teminatlar'],
        ['329', 'Diğer Ticari Borçlar'],
      ]},
      { code: '33', name: 'Diğer Borçlar', accounts: [
        ['331', 'Ortaklara Borçlar'],
        ['332', 'İştiraklere Borçlar'],
        ['333', 'Bağlı Ortaklıklara Borçlar'],
        ['335', 'Personele Borçlar'],
        ['336', 'Diğer Çeşitli Borçlar'],
      ]},
      { code: '34', name: 'Alınan Avanslar', accounts: [
        ['340', 'Alınan Sipariş Avansları'],
        ['349', 'Alınan Diğer Avanslar'],
      ]},
      { code: '36', name: 'Ödenecek Vergi ve Diğer Yükümlülükler', accounts: [
        ['360', 'Ödenecek Vergi ve Fonlar'],
        ['361', 'Ödenecek Sosyal Güvenlik Kesintileri'],
        ['368', 'Vadesi Geçmiş Ertelenmiş veya Taksitlendirilmiş Vergi ve Diğer Yükümlülükler'],
        ['369', 'Ödenecek Diğer Yükümlülükler'],
      ]},
      { code: '37', name: 'Borç ve Gider Karşılıkları', accounts: [
        ['370', 'Dönem Kârı Vergi ve Diğer Yasal Yükümlülük Karşılıkları'],
        ['371', 'Dönem Kârının Peşin Ödenen Vergi ve Diğer Yükümlülükleri (-)'],
        ['372', 'Kıdem Tazminatı Karşılığı'],
        ['373', 'Maliyet Giderleri Karşılığı'],
      ]},
      { code: '39', name: 'Diğer Kısa Vadeli Yabancı Kaynaklar', accounts: [
        ['391', 'Hesaplanan KDV'],
        ['392', 'Diğer KDV'],
        ['395', 'Merkez ve Şubeler Cari Hesabı'],
        ['397', 'Sayım ve Tesellüm Fazlaları'],
        ['399', 'Diğer Çeşitli Yabancı Kaynaklar'],
      ]},
    ],
  },
  {
    code: '4', name: 'Uzun Vadeli Yabancı Kaynaklar', type: 'liability',
    groups: [
      { code: '40', name: 'Mali Borçlar', accounts: [
        ['400', 'Banka Kredileri'],
        ['405', 'Çıkarılmış Tahviller'],
        ['407', 'Çıkarılmış Diğer Menkul Kıymetler'],
        ['408', 'Menkul Kıymetler İhraç Farkı (-)'],
        ['409', 'Diğer Mali Borçlar'],
      ]},
      { code: '42', name: 'Ticari Borçlar', accounts: [
        ['420', 'Satıcılar'],
        ['421', 'Borç Senetleri'],
        ['426', 'Alınan Depozito ve Teminatlar'],
        ['429', 'Diğer Ticari Borçlar'],
      ]},
    ],
  },
  {
    code: '5', name: 'Öz Kaynaklar', type: 'equity',
    groups: [
      { code: '50', name: 'Ödenmiş Sermaye', accounts: [
        ['500', 'Sermaye'],
        ['501', 'Ödenmemiş Sermaye (-)'],
      ]},
      { code: '52', name: 'Sermaye Yedekleri', accounts: [
        ['520', 'Hisse Senedi İhraç Primleri'],
        ['521', 'Hisse Senedi İptal Kârları'],
        ['522', 'M.D.V. Yeniden Değerleme Artışları'],
      ]},
      { code: '54', name: 'Kâr Yedekleri', accounts: [
        ['540', 'Yasal Yedekler'],
        ['541', 'Statü Yedekleri'],
        ['542', 'Olağanüstü Yedekler'],
      ]},
      { code: '57', name: 'Geçmiş Yıllar Kârları', accounts: [
        ['570', 'Geçmiş Yıllar Kârları'],
      ]},
      { code: '58', name: 'Geçmiş Yıllar Zararları', accounts: [
        ['580', 'Geçmiş Yıllar Zararları (-)'],
      ]},
      { code: '59', name: 'Dönem Net Kârı (Zararı)', accounts: [
        ['590', 'Dönem Net Kârı'],
        ['591', 'Dönem Net Zararı (-)'],
      ]},
    ],
  },
  // Section 6 is mixed — revenue + expense + equity. Top-level marked revenue
  // as a coarse default; subgroups override per TDHP rules below.
  {
    code: '6', name: 'Gelir Tablosu Hesapları', type: 'revenue',
    groups: [
      { code: '60', name: 'Brüt Satışlar', type: 'revenue', accounts: [
        ['600', 'Yurtiçi Satışlar'],
        ['601', 'Yurtdışı Satışlar'],
        ['602', 'Diğer Gelirler'],
      ]},
      { code: '61', name: 'Satış İndirimleri', type: 'expense', accounts: [
        ['610', 'Satıştan İadeler (-)'],
        ['611', 'Satış İskontoları (-)'],
        ['612', 'Diğer İndirimler (-)'],
      ]},
      { code: '62', name: 'Satışların Maliyeti', type: 'expense', accounts: [
        ['620', 'Satılan Mamuller Maliyeti (-)'],
        ['621', 'Satılan Ticari Mallar Maliyeti (-)'],
        ['622', 'Satılan Hizmet Maliyeti (-)'],
        ['623', 'Diğer Satışların Maliyeti (-)'],
      ]},
      { code: '63', name: 'Faaliyet Giderleri', type: 'expense', accounts: [
        ['630', 'Araştırma ve Geliştirme Giderleri (-)'],
        ['631', 'Pazarlama, Satış ve Dağıtım Giderleri (-)'],
        ['632', 'Genel Yönetim Giderleri (-)'],
      ]},
      { code: '64', name: 'Diğer Faaliyetlerden Olağan Gelir ve Kârlar', type: 'revenue', accounts: [
        ['640', 'İştiraklerden Temettü Gelirleri'],
        ['641', 'Bağlı Ortaklıklardan Temettü Gelirleri'],
        ['642', 'Faiz Gelirleri'],
        ['643', 'Komisyon Gelirleri'],
        ['644', 'Konusu Kalmayan Karşılıklar'],
        ['645', 'Menkul Kıymet Satış Kârları'],
        ['646', 'Kambiyo Kârları'],
        ['647', 'Reeskont Faiz Gelirleri'],
        ['649', 'Diğer Olağan Gelir ve Kârlar'],
      ]},
      { code: '65', name: 'Diğer Faaliyetlerden Olağan Gider ve Zararlar', type: 'expense', accounts: [
        ['653', 'Komisyon Giderleri (-)'],
        ['654', 'Karşılık Giderleri (-)'],
        ['655', 'Menkul Kıymet Satış Zararları (-)'],
        ['656', 'Kambiyo Zararları (-)'],
        ['657', 'Reeskont Faiz Giderleri (-)'],
        ['659', 'Diğer Olağan Gider ve Zararlar (-)'],
      ]},
      { code: '66', name: 'Finansman Giderleri', type: 'expense', accounts: [
        ['660', 'Kısa Vadeli Borçlanma Giderleri (-)'],
        ['661', 'Uzun Vadeli Borçlanma Giderleri (-)'],
      ]},
      { code: '67', name: 'Olağandışı Gelir ve Kârlar', type: 'revenue', accounts: [
        ['671', 'Önceki Dönem Gelir ve Kârları'],
        ['679', 'Diğer Olağandışı Gelir ve Kârlar'],
      ]},
      { code: '68', name: 'Olağandışı Gider ve Zararlar', type: 'expense', accounts: [
        ['680', 'Çalışmayan Kısım Gider ve Zararları (-)'],
        ['681', 'Önceki Dönem Gider ve Zararları (-)'],
        ['689', 'Diğer Olağandışı Gider ve Zararlar (-)'],
      ]},
      // 69 is transitional / clearing — classified as equity per spec
      { code: '69', name: 'Dönem Net Kâr veya Zararı', type: 'equity', accounts: [
        ['690', 'Dönem Kârı veya Zararı'],
        ['691', 'Dönem Kârı Vergi ve Diğer Yasal Yükümlülük Karşılıkları (-)'],
        ['692', 'Dönem Net Kârı veya Zararı'],
      ]},
    ],
  },
  {
    code: '7', name: 'Maliyet Hesapları', type: 'cost',
    groups: [
      { code: '71', name: 'Direkt İlk Madde ve Malzeme Giderleri', accounts: [
        ['710', 'Direkt İlk Madde ve Malzeme Giderleri'],
        ['711', 'Direkt İlk Madde ve Malzeme Yansıtma Hesabı'],
        ['712', 'Direkt İlk Madde ve Malzeme Fiyat Farkı'],
        ['713', 'Direkt İlk Madde ve Malzeme Miktar Farkı'],
      ]},
      { code: '72', name: 'Direkt İşçilik Giderleri', accounts: [
        ['720', 'Direkt İşçilik Giderleri'],
        ['721', 'Direkt İşçilik Giderleri Yansıtma Hesabı'],
        ['722', 'Direkt İşçilik Ücret Farkları'],
        ['723', 'Direkt İşçilik Süre (Zaman) Farkları'],
      ]},
      { code: '73', name: 'Genel Üretim Giderleri', accounts: [
        ['730', 'Genel Üretim Giderleri'],
        ['731', 'Genel Üretim Giderleri Yansıtma Hesabı'],
        ['732', 'Genel Üretim Giderleri Bütçe Farkları'],
        ['733', 'Genel Üretim Giderleri Verimlilik Farkları'],
        ['734', 'Genel Üretim Giderleri Kapasite Farkları'],
      ]},
      { code: '74', name: 'Hizmet Üretim Maliyeti', accounts: [
        ['740', 'Hizmet Üretim Maliyeti'],
        ['741', 'Hizmet Üretim Maliyeti Yansıtma Hesabı'],
        ['742', 'Hizmet Üretim Maliyeti Fark Hesapları'],
      ]},
      { code: '75', name: 'Araştırma ve Geliştirme Giderleri', accounts: [
        ['750', 'Araştırma ve Geliştirme Giderleri'],
        ['751', 'Araştırma ve Geliştirme Giderleri Yansıtma Hesabı'],
        ['752', 'Araştırma ve Geliştirme Gider Farkları'],
      ]},
      { code: '76', name: 'Pazarlama Satış ve Dağıtım Giderleri', accounts: [
        ['760', 'Pazarlama Satış ve Dağıtım Giderleri'],
        ['761', 'Pazarlama Satış ve Dağıtım Giderleri Yansıtma Hesabı'],
        ['762', 'Pazarlama Satış ve Dağıtım Giderleri Fark Hesabı'],
      ]},
      { code: '77', name: 'Genel Yönetim Giderleri', accounts: [
        ['770', 'Genel Yönetim Giderleri'],
        ['771', 'Genel Yönetim Giderleri Yansıtma Hesabı'],
        ['772', 'Genel Yönetim Gider Farkları'],
      ]},
      { code: '78', name: 'Finansman Giderleri', accounts: [
        ['780', 'Finansman Giderleri'],
        ['781', 'Finansman Giderleri Yansıtma Hesabı'],
        ['782', 'Finansman Giderleri Fark Hesabı'],
      ]},
    ],
  },
];

// ─── Flatten ──────────────────────────────────────────────────────────

function flatten() {
  const rows = [];
  for (const section of TREE) {
    rows.push({ code: section.code, name: section.name, type: section.type, level: 1, parent_code: null });
    for (const group of section.groups) {
      const groupType = group.type || section.type;
      rows.push({ code: group.code, name: group.name, type: groupType, level: 2, parent_code: section.code });
      for (const [accCode, accName] of group.accounts) {
        rows.push({ code: accCode, name: accName, type: groupType, level: 3, parent_code: group.code });
      }
    }
  }
  return rows;
}

function escape(s) { return String(s).replace(/'/g, "''"); }

function generateSql() {
  const rows = flatten();
  const valueLines = rows.map(r =>
    `  (v_company_id, '${r.code}', '${escape(r.name)}', '${escape(r.name)}', '${r.type}', ${r.level}, ${r.parent_code ? `'${r.parent_code}'` : 'NULL'}, 'TR', false, true)`
  ).join(',\n');

  return `-- ============================================================
-- M068: Rebuild Turkish TDHP chart_of_accounts for PARK GROUP
-- ============================================================
-- PARK GROUP'un önceki yüklemeleri (karışık ülke şablonu denemeleri) sildi
-- ve resmi Türkiye Tekdüzen Hesap Planı'nı yeniden seed eder.
-- ${rows.length} hesap — sadece company_id=PARK, diğer şirketler etkilenmez.
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_company_id uuid;
  v_count int;
BEGIN
  SELECT id INTO v_company_id FROM companies WHERE name ILIKE '%PARK%' AND deleted_at IS NULL LIMIT 1;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'PARK company not found';
  END IF;

  -- Wipe existing chart_of_accounts for this company (safe: no journal_entries
  -- or non-zero balances reference them — verified before migration).
  DELETE FROM chart_of_accounts WHERE company_id = v_company_id;

  -- Insert full Turkish TDHP
  INSERT INTO chart_of_accounts (company_id, code, name, name_local, type, level, parent_code, country_code, is_system, is_active) VALUES
${valueLines};

  -- Resolve parent_id from parent_code within the same company.
  UPDATE chart_of_accounts c
  SET parent_id = p.id
  FROM chart_of_accounts p
  WHERE c.company_id = v_company_id
    AND p.company_id = v_company_id
    AND c.parent_code = p.code
    AND c.parent_id IS NULL;

  SELECT COUNT(*) INTO v_count FROM chart_of_accounts WHERE company_id = v_company_id;
  RAISE NOTICE 'PARK GROUP chart_of_accounts rebuilt: % rows', v_count;
END $$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('068_turkey_coa_parkgroup_rebuild.sql',
  'PARK GROUP: Türkiye TDHP ${rows.length} hesap (resmi kodlar) — şablon sorunlu olduğu için tek şirkete özel rebuild.')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
`;
}

const sql = generateSql();
const outPath = path.join(__dirname, '../seeds/068_turkey_coa_parkgroup_rebuild.sql');
fs.writeFileSync(outPath, sql, 'utf8');

const rowCount = flatten().length;
const byType = {};
flatten().forEach(r => { byType[r.type] = (byType[r.type] || 0) + 1; });
console.log(`Wrote ${outPath}`);
console.log(`Total rows: ${rowCount}`);
console.log('By type:', byType);
