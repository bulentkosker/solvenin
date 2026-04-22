#!/usr/bin/env node
/**
 * Generates the Turkish Tekdüzen Hesap Planı as two SQL artifacts:
 *
 *   seeds/068_turkey_coa_parkgroup_rebuild.sql  — wipes & rebuilds PARK
 *   seeds/069_turkey_coa_template_rebuild.sql   — wipes & rebuilds the
 *                                                 TR rows in the
 *                                                 chart_of_accounts_templates
 *                                                 master table.
 *
 * Single source of truth: TREE below. Each leaf carries a Turkish name
 * and an English canonical name; sections/groups auto-generate both.
 */

const fs = require('fs');
const path = require('path');

// ─── Data ──────────────────────────────────────────────────────────────
// Schema per account: [code, name_tr, name_en]. Group/section carry their
// own names; children inherit type unless the group overrides it.
const TREE = [
  {
    code: '1', name_tr: 'Dönen Varlıklar', name_en: 'Current Assets', type: 'asset',
    groups: [
      { code: '10', name_tr: 'Hazır Değerler', name_en: 'Cash and Cash Equivalents', accounts: [
        ['100', 'Kasa',                              'Cash on Hand'],
        ['101', 'Alınan Çekler',                     'Cheques Received'],
        ['102', 'Bankalar',                          'Banks'],
        ['103', 'Verilen Çekler ve Ödeme Emirleri (-)', 'Cheques Given and Payment Orders (-)'],
        ['108', 'Diğer Hazır Değerler',              'Other Cash and Cash Equivalents'],
      ]},
      { code: '12', name_tr: 'Ticari Alacaklar', name_en: 'Trade Receivables', accounts: [
        ['120', 'Alıcılar',                           'Trade Debtors'],
        ['121', 'Alacak Senetleri',                   'Notes Receivable'],
        ['127', 'Diğer Ticari Alacaklar',             'Other Trade Receivables'],
        ['128', 'Şüpheli Ticari Alacaklar',           'Doubtful Trade Receivables'],
        ['129', 'Şüpheli Alacaklar Karşılığı (-)',    'Provision for Doubtful Receivables (-)'],
      ]},
      { code: '13', name_tr: 'Diğer Alacaklar', name_en: 'Other Receivables', accounts: [
        ['131', 'Ortaklardan Alacaklar',              'Receivables from Shareholders'],
        ['132', 'İştiraklerden Alacaklar',            'Receivables from Affiliates'],
        ['133', 'Bağlı Ortaklıklardan Alacaklar',     'Receivables from Subsidiaries'],
        ['135', 'Personelden Alacaklar',              'Receivables from Employees'],
        ['136', 'Diğer Çeşitli Alacaklar',            'Other Miscellaneous Receivables'],
      ]},
      { code: '15', name_tr: 'Stoklar', name_en: 'Inventories', accounts: [
        ['150', 'İlk Madde ve Malzeme',               'Raw Materials and Supplies'],
        ['151', 'Yarı Mamuller',                      'Work in Process'],
        ['152', 'Mamuller',                           'Finished Goods'],
        ['153', 'Ticari Mallar',                      'Merchandise'],
        ['157', 'Diğer Stoklar',                      'Other Inventories'],
        ['158', 'Stok Değer Düşüklüğü Karşılığı (-)', 'Provision for Inventory Impairment (-)'],
      ]},
      { code: '19', name_tr: 'Diğer Dönen Varlıklar', name_en: 'Other Current Assets', accounts: [
        ['190', 'Devreden KDV',                       'Carried Forward VAT'],
        ['191', 'İndirilecek KDV',                    'Deductible VAT'],
        ['192', 'Diğer KDV',                          'Other VAT'],
        ['195', 'İş Avansları',                       'Business Advances'],
        ['196', 'Personel Avansları',                 'Employee Advances'],
        ['197', 'Sayım ve Tesellüm Noksanları',       'Counting and Receipt Shortages'],
        ['199', 'Diğer Çeşitli Dönen Varlıklar',      'Other Miscellaneous Current Assets'],
      ]},
    ],
  },
  {
    code: '2', name_tr: 'Duran Varlıklar', name_en: 'Non-Current Assets', type: 'asset',
    groups: [
      { code: '22', name_tr: 'Ticari Alacaklar', name_en: 'Trade Receivables', accounts: [
        ['220', 'Alıcılar',                           'Trade Debtors'],
        ['221', 'Alacak Senetleri',                   'Notes Receivable'],
      ]},
      { code: '25', name_tr: 'Maddi Duran Varlıklar', name_en: 'Tangible Fixed Assets', accounts: [
        ['250', 'Arazi ve Arsalar',                   'Land and Plots'],
        ['251', 'Yeraltı ve Yerüstü Düzenleri',       'Underground and Surface Structures'],
        ['252', 'Binalar',                            'Buildings'],
        ['253', 'Tesis, Makine ve Cihazlar',          'Plant, Machinery and Equipment'],
        ['254', 'Taşıtlar',                           'Vehicles'],
        ['255', 'Demirbaşlar',                        'Furniture and Fixtures'],
        ['256', 'Diğer Maddi Duran Varlıklar',        'Other Tangible Fixed Assets'],
        ['257', 'Birikmiş Amortismanlar (-)',         'Accumulated Depreciation (-)'],
        ['258', 'Yapılmakta Olan Yatırımlar',         'Construction in Progress'],
        ['259', 'Verilen Avanslar',                   'Advances Given'],
      ]},
      { code: '26', name_tr: 'Maddi Olmayan Duran Varlıklar', name_en: 'Intangible Fixed Assets', accounts: [
        ['260', 'Haklar',                             'Rights'],
        ['261', 'Şerefiye',                           'Goodwill'],
        ['262', 'Kuruluş ve Örgütlenme Giderleri',    'Pre-operating and Organizational Expenses'],
        ['263', 'Araştırma ve Geliştirme Giderleri',  'Research and Development Expenses'],
        ['264', 'Özel Maliyetler',                    'Special Costs'],
        ['267', 'Diğer Maddi Olmayan Duran Varlıklar','Other Intangible Fixed Assets'],
        ['268', 'Birikmiş Amortismanlar (-)',         'Accumulated Amortization (-)'],
      ]},
    ],
  },
  {
    code: '3', name_tr: 'Kısa Vadeli Yabancı Kaynaklar', name_en: 'Current Liabilities', type: 'liability',
    groups: [
      { code: '30', name_tr: 'Mali Borçlar', name_en: 'Financial Payables', accounts: [
        ['300', 'Banka Kredileri',                    'Bank Loans'],
        ['303', 'Uzun Vadeli Kredilerin Anapara Taksitleri', 'Current Portion of Long-Term Loans'],
        ['304', 'Tahvil Anapara Borç Taksit ve Faizleri',    'Bond Principal Instalments and Interest'],
        ['308', 'Menkul Kıymetler İhraç Farkı',              'Securities Issue Premium'],
      ]},
      { code: '32', name_tr: 'Ticari Borçlar', name_en: 'Trade Payables', accounts: [
        ['320', 'Satıcılar',                          'Suppliers'],
        ['321', 'Borç Senetleri',                     'Notes Payable'],
        ['322', 'Borç Senetleri Reeskontu (-)',       'Discount on Notes Payable (-)'],
        ['326', 'Alınan Depozito ve Teminatlar',      'Deposits and Guarantees Received'],
        ['329', 'Diğer Ticari Borçlar',               'Other Trade Payables'],
      ]},
      { code: '33', name_tr: 'Diğer Borçlar', name_en: 'Other Payables', accounts: [
        ['331', 'Ortaklara Borçlar',                  'Payables to Shareholders'],
        ['332', 'İştiraklere Borçlar',                'Payables to Affiliates'],
        ['333', 'Bağlı Ortaklıklara Borçlar',         'Payables to Subsidiaries'],
        ['335', 'Personele Borçlar',                  'Payables to Employees'],
        ['336', 'Diğer Çeşitli Borçlar',              'Other Miscellaneous Payables'],
      ]},
      { code: '34', name_tr: 'Alınan Avanslar', name_en: 'Advances Received', accounts: [
        ['340', 'Alınan Sipariş Avansları',           'Order Advances Received'],
        ['349', 'Alınan Diğer Avanslar',              'Other Advances Received'],
      ]},
      { code: '36', name_tr: 'Ödenecek Vergi ve Diğer Yükümlülükler', name_en: 'Taxes and Other Liabilities Payable', accounts: [
        ['360', 'Ödenecek Vergi ve Fonlar',           'Taxes and Funds Payable'],
        ['361', 'Ödenecek Sosyal Güvenlik Kesintileri','Social Security Withholdings Payable'],
        ['368', 'Vadesi Geçmiş Ertelenmiş veya Taksitlendirilmiş Vergi ve Diğer Yükümlülükler', 'Overdue, Deferred or Instalment Tax Liabilities'],
        ['369', 'Ödenecek Diğer Yükümlülükler',       'Other Liabilities Payable'],
      ]},
      { code: '37', name_tr: 'Borç ve Gider Karşılıkları', name_en: 'Provisions for Liabilities and Expenses', accounts: [
        ['370', 'Dönem Kârı Vergi ve Diğer Yasal Yükümlülük Karşılıkları', 'Current Period Profit Tax and Legal Liability Provisions'],
        ['371', 'Dönem Kârının Peşin Ödenen Vergi ve Diğer Yükümlülükleri (-)', 'Prepaid Taxes on Current Period Profit (-)'],
        ['372', 'Kıdem Tazminatı Karşılığı',          'Severance Pay Provision'],
        ['373', 'Maliyet Giderleri Karşılığı',        'Cost Expense Provision'],
      ]},
      { code: '39', name_tr: 'Diğer Kısa Vadeli Yabancı Kaynaklar', name_en: 'Other Current Liabilities', accounts: [
        ['391', 'Hesaplanan KDV',                     'Output VAT'],
        ['392', 'Diğer KDV',                          'Other VAT'],
        ['395', 'Merkez ve Şubeler Cari Hesabı',      'Head Office and Branches Current Account'],
        ['397', 'Sayım ve Tesellüm Fazlaları',        'Counting and Receipt Surpluses'],
        ['399', 'Diğer Çeşitli Yabancı Kaynaklar',    'Other Miscellaneous Liabilities'],
      ]},
    ],
  },
  {
    code: '4', name_tr: 'Uzun Vadeli Yabancı Kaynaklar', name_en: 'Long-Term Liabilities', type: 'liability',
    groups: [
      { code: '40', name_tr: 'Mali Borçlar', name_en: 'Financial Payables', accounts: [
        ['400', 'Banka Kredileri',                    'Bank Loans'],
        ['405', 'Çıkarılmış Tahviller',               'Issued Bonds'],
        ['407', 'Çıkarılmış Diğer Menkul Kıymetler',  'Other Issued Securities'],
        ['408', 'Menkul Kıymetler İhraç Farkı (-)',   'Securities Issue Discount (-)'],
        ['409', 'Diğer Mali Borçlar',                 'Other Financial Payables'],
      ]},
      { code: '42', name_tr: 'Ticari Borçlar', name_en: 'Trade Payables', accounts: [
        ['420', 'Satıcılar',                          'Suppliers'],
        ['421', 'Borç Senetleri',                     'Notes Payable'],
        ['426', 'Alınan Depozito ve Teminatlar',      'Deposits and Guarantees Received'],
        ['429', 'Diğer Ticari Borçlar',               'Other Trade Payables'],
      ]},
    ],
  },
  {
    code: '5', name_tr: 'Öz Kaynaklar', name_en: 'Equity', type: 'equity',
    groups: [
      { code: '50', name_tr: 'Ödenmiş Sermaye', name_en: 'Paid-in Capital', accounts: [
        ['500', 'Sermaye',                            'Capital'],
        ['501', 'Ödenmemiş Sermaye (-)',              'Unpaid Capital (-)'],
      ]},
      { code: '52', name_tr: 'Sermaye Yedekleri', name_en: 'Capital Reserves', accounts: [
        ['520', 'Hisse Senedi İhraç Primleri',        'Share Premium'],
        ['521', 'Hisse Senedi İptal Kârları',         'Gains on Share Cancellation'],
        ['522', 'M.D.V. Yeniden Değerleme Artışları', 'Revaluation Increases on Tangible Fixed Assets'],
      ]},
      { code: '54', name_tr: 'Kâr Yedekleri', name_en: 'Profit Reserves', accounts: [
        ['540', 'Yasal Yedekler',                     'Legal Reserves'],
        ['541', 'Statü Yedekleri',                    'Statutory Reserves'],
        ['542', 'Olağanüstü Yedekler',                'Extraordinary Reserves'],
      ]},
      { code: '57', name_tr: 'Geçmiş Yıllar Kârları', name_en: 'Prior Years Profits', accounts: [
        ['570', 'Geçmiş Yıllar Kârları',              'Prior Years Profits'],
      ]},
      { code: '58', name_tr: 'Geçmiş Yıllar Zararları', name_en: 'Prior Years Losses', accounts: [
        ['580', 'Geçmiş Yıllar Zararları (-)',        'Prior Years Losses (-)'],
      ]},
      { code: '59', name_tr: 'Dönem Net Kârı (Zararı)', name_en: 'Current Period Net Profit (Loss)', accounts: [
        ['590', 'Dönem Net Kârı',                     'Current Period Net Profit'],
        ['591', 'Dönem Net Zararı (-)',               'Current Period Net Loss (-)'],
      ]},
    ],
  },
  {
    code: '6', name_tr: 'Gelir Tablosu Hesapları', name_en: 'Income Statement Accounts', type: 'revenue',
    groups: [
      { code: '60', name_tr: 'Brüt Satışlar', name_en: 'Gross Sales', type: 'revenue', accounts: [
        ['600', 'Yurtiçi Satışlar',                   'Domestic Sales'],
        ['601', 'Yurtdışı Satışlar',                  'Export Sales'],
        ['602', 'Diğer Gelirler',                     'Other Revenues'],
      ]},
      { code: '61', name_tr: 'Satış İndirimleri', name_en: 'Sales Deductions', type: 'expense', accounts: [
        ['610', 'Satıştan İadeler (-)',               'Sales Returns (-)'],
        ['611', 'Satış İskontoları (-)',              'Sales Discounts (-)'],
        ['612', 'Diğer İndirimler (-)',               'Other Deductions (-)'],
      ]},
      { code: '62', name_tr: 'Satışların Maliyeti', name_en: 'Cost of Sales', type: 'expense', accounts: [
        ['620', 'Satılan Mamuller Maliyeti (-)',      'Cost of Finished Goods Sold (-)'],
        ['621', 'Satılan Ticari Mallar Maliyeti (-)', 'Cost of Merchandise Sold (-)'],
        ['622', 'Satılan Hizmet Maliyeti (-)',        'Cost of Services Sold (-)'],
        ['623', 'Diğer Satışların Maliyeti (-)',      'Cost of Other Sales (-)'],
      ]},
      { code: '63', name_tr: 'Faaliyet Giderleri', name_en: 'Operating Expenses', type: 'expense', accounts: [
        ['630', 'Araştırma ve Geliştirme Giderleri (-)',      'Research and Development Expenses (-)'],
        ['631', 'Pazarlama, Satış ve Dağıtım Giderleri (-)',  'Marketing, Selling and Distribution Expenses (-)'],
        ['632', 'Genel Yönetim Giderleri (-)',                'General Administrative Expenses (-)'],
      ]},
      { code: '64', name_tr: 'Diğer Faaliyetlerden Olağan Gelir ve Kârlar', name_en: 'Other Ordinary Operating Income and Profits', type: 'revenue', accounts: [
        ['640', 'İştiraklerden Temettü Gelirleri',    'Dividend Income from Affiliates'],
        ['641', 'Bağlı Ortaklıklardan Temettü Gelirleri', 'Dividend Income from Subsidiaries'],
        ['642', 'Faiz Gelirleri',                     'Interest Income'],
        ['643', 'Komisyon Gelirleri',                 'Commission Income'],
        ['644', 'Konusu Kalmayan Karşılıklar',        'Reversed Provisions'],
        ['645', 'Menkul Kıymet Satış Kârları',        'Gains on Securities Sales'],
        ['646', 'Kambiyo Kârları',                    'Foreign Exchange Gains'],
        ['647', 'Reeskont Faiz Gelirleri',            'Rediscount Interest Income'],
        ['649', 'Diğer Olağan Gelir ve Kârlar',       'Other Ordinary Income and Profits'],
      ]},
      { code: '65', name_tr: 'Diğer Faaliyetlerden Olağan Gider ve Zararlar', name_en: 'Other Ordinary Operating Expenses and Losses', type: 'expense', accounts: [
        ['653', 'Komisyon Giderleri (-)',             'Commission Expenses (-)'],
        ['654', 'Karşılık Giderleri (-)',             'Provision Expenses (-)'],
        ['655', 'Menkul Kıymet Satış Zararları (-)',  'Losses on Securities Sales (-)'],
        ['656', 'Kambiyo Zararları (-)',              'Foreign Exchange Losses (-)'],
        ['657', 'Reeskont Faiz Giderleri (-)',        'Rediscount Interest Expenses (-)'],
        ['659', 'Diğer Olağan Gider ve Zararlar (-)', 'Other Ordinary Expenses and Losses (-)'],
      ]},
      { code: '66', name_tr: 'Finansman Giderleri', name_en: 'Financing Expenses', type: 'expense', accounts: [
        ['660', 'Kısa Vadeli Borçlanma Giderleri (-)','Short-Term Borrowing Expenses (-)'],
        ['661', 'Uzun Vadeli Borçlanma Giderleri (-)','Long-Term Borrowing Expenses (-)'],
      ]},
      { code: '67', name_tr: 'Olağandışı Gelir ve Kârlar', name_en: 'Extraordinary Income and Profits', type: 'revenue', accounts: [
        ['671', 'Önceki Dönem Gelir ve Kârları',      'Prior Period Income and Profits'],
        ['679', 'Diğer Olağandışı Gelir ve Kârlar',   'Other Extraordinary Income and Profits'],
      ]},
      { code: '68', name_tr: 'Olağandışı Gider ve Zararlar', name_en: 'Extraordinary Expenses and Losses', type: 'expense', accounts: [
        ['680', 'Çalışmayan Kısım Gider ve Zararları (-)', 'Idle Capacity Expenses and Losses (-)'],
        ['681', 'Önceki Dönem Gider ve Zararları (-)',     'Prior Period Expenses and Losses (-)'],
        ['689', 'Diğer Olağandışı Gider ve Zararlar (-)',  'Other Extraordinary Expenses and Losses (-)'],
      ]},
      { code: '69', name_tr: 'Dönem Net Kâr veya Zararı', name_en: 'Current Period Net Profit or Loss', type: 'equity', accounts: [
        ['690', 'Dönem Kârı veya Zararı',             'Period Profit or Loss'],
        ['691', 'Dönem Kârı Vergi ve Diğer Yasal Yükümlülük Karşılıkları (-)', 'Period Profit Tax and Legal Liability Provisions (-)'],
        ['692', 'Dönem Net Kârı veya Zararı',         'Current Period Net Profit or Loss'],
      ]},
    ],
  },
  {
    code: '7', name_tr: 'Maliyet Hesapları', name_en: 'Cost Accounts', type: 'cost',
    groups: [
      { code: '71', name_tr: 'Direkt İlk Madde ve Malzeme Giderleri', name_en: 'Direct Raw Material and Supplies Expenses', accounts: [
        ['710', 'Direkt İlk Madde ve Malzeme Giderleri',              'Direct Raw Material and Supplies Expenses'],
        ['711', 'Direkt İlk Madde ve Malzeme Yansıtma Hesabı',        'Direct Raw Material and Supplies Allocation Account'],
        ['712', 'Direkt İlk Madde ve Malzeme Fiyat Farkı',            'Direct Raw Material Price Variance'],
        ['713', 'Direkt İlk Madde ve Malzeme Miktar Farkı',           'Direct Raw Material Quantity Variance'],
      ]},
      { code: '72', name_tr: 'Direkt İşçilik Giderleri', name_en: 'Direct Labor Expenses', accounts: [
        ['720', 'Direkt İşçilik Giderleri',                           'Direct Labor Expenses'],
        ['721', 'Direkt İşçilik Giderleri Yansıtma Hesabı',           'Direct Labor Allocation Account'],
        ['722', 'Direkt İşçilik Ücret Farkları',                      'Direct Labor Rate Variance'],
        ['723', 'Direkt İşçilik Süre (Zaman) Farkları',               'Direct Labor Time Variance'],
      ]},
      { code: '73', name_tr: 'Genel Üretim Giderleri', name_en: 'Manufacturing Overhead', accounts: [
        ['730', 'Genel Üretim Giderleri',                             'Manufacturing Overhead'],
        ['731', 'Genel Üretim Giderleri Yansıtma Hesabı',             'Manufacturing Overhead Allocation Account'],
        ['732', 'Genel Üretim Giderleri Bütçe Farkları',              'Manufacturing Overhead Budget Variance'],
        ['733', 'Genel Üretim Giderleri Verimlilik Farkları',         'Manufacturing Overhead Efficiency Variance'],
        ['734', 'Genel Üretim Giderleri Kapasite Farkları',           'Manufacturing Overhead Capacity Variance'],
      ]},
      { code: '74', name_tr: 'Hizmet Üretim Maliyeti', name_en: 'Service Production Cost', accounts: [
        ['740', 'Hizmet Üretim Maliyeti',                             'Service Production Cost'],
        ['741', 'Hizmet Üretim Maliyeti Yansıtma Hesabı',             'Service Production Cost Allocation Account'],
        ['742', 'Hizmet Üretim Maliyeti Fark Hesapları',              'Service Production Cost Variance Accounts'],
      ]},
      { code: '75', name_tr: 'Araştırma ve Geliştirme Giderleri', name_en: 'Research and Development Expenses', accounts: [
        ['750', 'Araştırma ve Geliştirme Giderleri',                  'Research and Development Expenses'],
        ['751', 'Araştırma ve Geliştirme Giderleri Yansıtma Hesabı',  'R&D Allocation Account'],
        ['752', 'Araştırma ve Geliştirme Gider Farkları',             'R&D Expense Variances'],
      ]},
      { code: '76', name_tr: 'Pazarlama Satış ve Dağıtım Giderleri', name_en: 'Marketing, Selling and Distribution Expenses', accounts: [
        ['760', 'Pazarlama Satış ve Dağıtım Giderleri',               'Marketing, Selling and Distribution Expenses'],
        ['761', 'Pazarlama Satış ve Dağıtım Giderleri Yansıtma Hesabı','Marketing, Selling and Distribution Allocation Account'],
        ['762', 'Pazarlama Satış ve Dağıtım Giderleri Fark Hesabı',   'Marketing, Selling and Distribution Variance Account'],
      ]},
      { code: '77', name_tr: 'Genel Yönetim Giderleri', name_en: 'General Administrative Expenses', accounts: [
        ['770', 'Genel Yönetim Giderleri',                            'General Administrative Expenses'],
        ['771', 'Genel Yönetim Giderleri Yansıtma Hesabı',            'General Administrative Allocation Account'],
        ['772', 'Genel Yönetim Gider Farkları',                       'General Administrative Expense Variances'],
      ]},
      { code: '78', name_tr: 'Finansman Giderleri', name_en: 'Financing Expenses', accounts: [
        ['780', 'Finansman Giderleri',                                'Financing Expenses'],
        ['781', 'Finansman Giderleri Yansıtma Hesabı',                'Financing Expenses Allocation Account'],
        ['782', 'Finansman Giderleri Fark Hesabı',                    'Financing Expenses Variance Account'],
      ]},
    ],
  },
];

// ─── Flatten ──────────────────────────────────────────────────────────

function flatten() {
  const rows = [];
  for (const section of TREE) {
    rows.push({ code: section.code, name_tr: section.name_tr, name_en: section.name_en,
                type: section.type, level: 1, parent_code: null });
    for (const group of section.groups) {
      const groupType = group.type || section.type;
      rows.push({ code: group.code, name_tr: group.name_tr, name_en: group.name_en,
                  type: groupType, level: 2, parent_code: section.code });
      for (const [code, name_tr, name_en] of group.accounts) {
        rows.push({ code, name_tr, name_en, type: groupType, level: 3, parent_code: group.code });
      }
    }
  }
  return rows;
}

function escape(s) { return String(s).replace(/'/g, "''"); }

// ─── PARK GROUP SQL (068) — per-company rebuild ───────────────────────

function generateParkGroupSql(rows) {
  const values = rows.map(r =>
    `  (v_company_id, '${r.code}', '${escape(r.name_tr)}', '${escape(r.name_tr)}', '${r.type}', ${r.level}, ${r.parent_code ? `'${r.parent_code}'` : 'NULL'}, 'TR', false, true)`
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
${values};

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

// ─── TEMPLATE SQL (069) — chart_of_accounts_templates for country_code='TR' ─

function generateTemplateSql(rows) {
  const values = rows.map(r =>
    `  ('TR', '${r.code}', '${escape(r.name_tr)}', '${escape(r.name_en)}', '${r.type}', ${r.parent_code ? `'${r.parent_code}'` : 'NULL'}, ${r.level}, true)`
  ).join(',\n');

  return `-- ============================================================
-- M069: Rebuild TR template in chart_of_accounts_templates
-- ============================================================
-- Şimdiye dek TR şablonu resmi TDHP ile uyumlu değildi. Yeni şirket
-- kurulduğunda veya Ayarlar > Muhasebe > Şablon Yükle akışı
-- (accounting.html:731) çağrıldığında buradan kopyalandığı için hatalı
-- veri yeniden üretiliyordu. ${rows.length} resmi TDHP hesabıyla değiştiriyor.
-- Başka ülke şablonları etkilenmez.
-- ============================================================

BEGIN;

DELETE FROM chart_of_accounts_templates WHERE country_code = 'TR';

INSERT INTO chart_of_accounts_templates
  (country_code, account_code, account_name_local, account_name_en, account_type, parent_code, level, is_mandatory)
VALUES
${values};

INSERT INTO migrations_log (file_name, notes)
VALUES ('069_turkey_coa_template_rebuild.sql',
  'TR template: resmi Türkiye TDHP ${rows.length} hesap (official codes + EN translations).')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
`;
}

// ─── Main ─────────────────────────────────────────────────────────────

const rows = flatten();
const parkPath = path.join(__dirname, '../seeds/068_turkey_coa_parkgroup_rebuild.sql');
const tplPath  = path.join(__dirname, '../seeds/069_turkey_coa_template_rebuild.sql');

fs.writeFileSync(parkPath, generateParkGroupSql(rows), 'utf8');
fs.writeFileSync(tplPath,  generateTemplateSql(rows),  'utf8');

const byType = {};
rows.forEach(r => { byType[r.type] = (byType[r.type] || 0) + 1; });
console.log(`Generated:`);
console.log(` - ${parkPath}`);
console.log(` - ${tplPath}`);
console.log(`Total rows: ${rows.length}`);
console.log('By type:', byType);
