# CRITICAL RULES — ALWAYS FOLLOW

## NO APPROVAL ASKING
NEVER ask for approval before making changes.
NEVER say "shall I proceed?", "should I make this change?",
"do you want me to?", "would you like me to?".
Just DO IT directly.

## NO CONFIRMATION STEPS
Do not ask "is this correct?", "does this look right?",
"should I continue?" — just proceed.

## EXCEPTIONS (only these require confirmation):
- Dropping/deleting database tables or columns
- Deleting production data
- Changing authentication or security settings

Everything else: just do it without asking.

---

# Solvenin ERP - Claude Code Bağlamı

## Proje Bilgileri
- GitHub: github.com/bulentkosker/solvenin
- Production: solvenin.com (Vercel)
- Supabase URL: https://jaakjdzpdizjbzvbtcld.supabase.co
- Stack: HTML/JS/CSS, Supabase, Vercel
- Dil: Türkçe öncelikli, 10 dil destekli

## Tamamlanan Modüller
Dashboard, Inventory, Sales, Purchasing, Production,
Cash&Bank, Accounting, HR, Shipping, Projects,
Maintenance, Settings, Subscription, Contacts, User Permissions

## Dosya Yapısı
- `*.html` — Sayfa modülleri (sales.html, purchasing.html, contacts.html vb.)
- `sidebar.js` — Sidebar navigasyon (IIFE, tüm sayfalarda)
- `i18n.js` — Çeviri sistemi (10 dil, ~900 key)
- `utils.js` — Global yardımcı fonksiyonlar (fmtNum, parseNum, fmt, fmtShort, submitting, withLoading, getErrorMessage)
- `quickadd.js` — Aranabilir dropdown bileşeni (QA.create)
- `permissions.js` — Modül izin kontrolü
- `theme.css` — Global tema (spinner kaldırma, tablo stilleri)
- `seeds/*.sql` — Supabase migration dosyaları
- `supabase/functions/` — Edge Functions

## Önemli Kararlar
- Plan kullanıcıya bağlı (profiles.plan), şirkete değil
- Müşteri+Tedarikçi → tek contacts tablosu (is_customer, is_supplier)
- Fatura limiti: Free planda 30/ay (sales_orders + purchase_orders)
- Modül yönetimi: company_modules tablosu
- Kullanıcı yönetimi: Edge Function (create-user), JWT verification OFF
- Hesap planları: 9 ülke, 822 hesap (chart_of_accounts_templates)
- Vergi oranları: tax_rates_templates tablosu
- Fatura formu: modal değil tam sayfa (?action=new, ?action=edit&id=XXX)
- Açıklama kolonu: varsayılan gizli, toggle ile açılır

## Veritabanı Önemli Tablolar
- `companies` — şirketler
- `profiles` — kullanıcı profilleri (plan, plan_interval, must_change_password)
- `company_users` — şirket-kullanıcı ilişkisi (role: owner/admin/manager/employee/accountant)
- `company_modules` — aktif modüller
- `contacts` — müşteri ve tedarikçiler (is_customer, is_supplier, type)
- `sales_orders` / `sales_order_items` — satış faturaları
- `purchase_orders` / `purchase_order_items` — alış faturaları
- `payments` — ödeme kayıtları
- `chart_of_accounts` — şirket hesap planı
- `chart_of_accounts_templates` — ülke bazlı şablonlar
- `tax_rates` — şirket vergi oranları
- `tax_rates_templates` — ülke bazlı şablonlar
- `user_permissions` — modül bazlı izinler (can_view, can_create, can_edit, can_delete)
- `exchange_rates` — döviz kurları
- `stock_movements` — stok hareketleri
- `warehouses` — depolar
- `cash_registers` / `bank_accounts` — kasa ve banka hesapları

## RLS Önemli Notlar
- `get_my_company_ids()` — SECURITY DEFINER, uuid[] döndürür, `= ANY()` ile kullan
- `get_my_admin_company_ids()` — owner/admin şirketler için INSERT policy
- `get_active_user_count(owner_uid)` — tüm şirketlerdeki unique aktif kullanıcı sayısı
- `get_monthly_invoice_count(p_company_id)` — aylık fatura sayısı (limit kontrolü)
- Infinite recursion riski: company_users'a referans veren policy'lerde SECURITY DEFINER kullan
- contacts, user_permissions: `= ANY(get_my_company_ids())` ile

## Supabase SQL Execution
- `exec_sql(query text)` — SECURITY DEFINER helper fonksiyonu
- Tüm migration'lar node + service key ile çalıştırılır (SQL Editor'e gerek yok)
- `.env` dosyasında: SUPABASE_URL, SUPABASE_SERVICE_KEY

## Migration Safety Rule (MANDATORY)
- Every migration SQL file MUST be wrapped in a transaction:
  ```sql
  BEGIN;
  -- all changes here
  INSERT INTO migrations_log (file_name, notes) VALUES ('NNN_name.sql', 'description')
    ON CONFLICT (file_name) DO NOTHING;
  COMMIT;
  ```
- This ensures if anything fails midway, the entire migration rolls back automatically
- No partial migrations allowed
- Every migration must have a corresponding INSERT into migrations_log at the end, inside the same transaction
- Violation of this rule is a bug — partial migrations corrupt data

## POS Module
- `pos.html` — full-screen POS interface (no sidebar)
- Product grid with category filter + search
- Cart with +/- quantity, real-time totals
- Payment: Cash (with change calc), Card, Bank Transfer
- Creates sales_order (order_type='pos', status='paid')
- Auto: stock movements, cash/bank transactions
- Tables: `pos_sessions`, `pos_cash_transfers`
- `sales_orders.order_type` — 'sale' (normal) or 'pos' (POS)
- `cash_transactions.payment_method` / `bank_transactions.payment_method`
- Cashier report in cashbank.html (tab: cashier-report)

## Accounting Integration
- `companies.accounting_enabled` — toggle in Settings > Entegrasyonlar
- When enabled: invoiced/paid orders auto-create journal entries
  - Sale invoice: Debit 120 (Receivables), Credit 600 (Revenue) + 391 (VAT)
  - Payment: Debit 100/102 (Cash/Bank), Credit 120 (Receivables)
- When enabled: invoiced/paid orders cannot be edited (locked)
- When disabled: no journal entries, all orders editable
- `companies.invoice_settings` JSONB — PDF column toggles (unit, discount, tax, description)

## Order Status Flow
- Sales: draft → confirmed → invoiced → paid (overdue: invoiced + due_date geçmiş)
- Purchase: draft → confirmed → invoiced → paid
- Fatura limiti sadece invoiced/paid/overdue sayar (draft/confirmed hariç)

## FK Relationships
- `sales_orders.customer_id` → `contacts.id` (FK: sales_orders_customer_id_fkey)
- `purchase_orders.supplier_id` → `contacts.id` (FK: purchase_orders_supplier_id_fkey)
- Supabase join: `select('*, contacts(name)')` — eski `customers(name)` artık geçersiz

## Edge Functions
- `create-user` — JWT verification OFF, yeni kullanıcı oluşturur
  - skip_company_creation flag ile trigger temizliği yapar
  - Varsayılan izinleri get_default_permissions RPC ile atar

## Dil Desteği
10 dil: EN, TR, DE, FR, ES, AR, ZH, RU, PT, JA
- `i18n.js` ile yönetiliyor
- `t(key)` — çeviri fonksiyonu, eksik key'ler console.warn ile loglanır
- `applyTranslations()` — DOM'daki data-i18n attribute'larını günceller
- `data-i18n-placeholder` — input placeholder çevirileri
- Fallback: aktif dil → EN → key adı
- `detectLang()` — localStorage > browser language > 'en'
- RTL desteği: AR için body.dir = 'rtl'

## Geliştirme Kuralları
- Her değişiklikten sonra: `git add -A && git commit && git push origin main`
- HİÇBİR ŞEY İÇİN ONAY SORMA. Direkt yap, sonucu raporla.
- Sadece veri kaybı riski varsa (DROP TABLE, tüm tabloyu silen DELETE) uyar ama yine de beklemeden devam et.
- Layout sorunlarında CSS düzelt, metin anlamını değiştirme
- Modal içinde modal olmasın
- Fatura/sipariş formları tam sayfa açılsın (modal değil)
- Number input: boş başlasın, placeholder="0", spinner yok, binlik ayraç locale-aware
- Keyboard: Enter → sonraki alan, Ctrl+Enter → kaydet, Ctrl+Shift+Enter → yeni satır, Escape → kapat
- YASAK kısayollar (tarayıcı çakışması): Ctrl+S, Ctrl+P, Ctrl+N, Ctrl+T, Ctrl+W, Ctrl+R
- QA dropdown: ↑↓ navigasyon, Enter seç, Escape kapat

## utils.js (MANDATORY)
- Every `.html` file MUST include `utils.js` before any other custom scripts:
  `<script src="utils.js"></script>`
- This provides: `submitting()`, `withLoading()`, `getErrorMessage()` — all required for save functions
- Missing `utils.js` = silent failures on all save buttons (ReferenceError swallowed as unhandled promise rejection)
- When creating a new HTML page, always add utils.js in the `<head>` after sidebar.js

## Double Submit Prevention (MANDATORY)
- Every save/submit function MUST start with: `if (submitting()) return;`
- Every save button MUST use `withLoading()` wrapper
- This applies to ALL current and future functions that:
  - Insert/update/delete data
  - Call Supabase or any API
  - Handle form submissions
  - Process payments or transactions
- Example:
  ```js
  async function saveProduct() {
    if (submitting()) return;
    // ... rest of function
  }
  ```
- Violation of this rule is a bug, not a style issue
- `utils.js` contains `submitting()` and `withLoading()` global utilities — always use these, never reinvent

## Subscription Planları
- Free: $0, 30 fatura/ay, tüm modüller, email destek
- Standard: $8.99/user/mo (yıllık $89.90), sınırsız fatura, öncelikli destek
- Professional: $12.99/user/mo (yıllık $129.90), çoklu şirket, öncelikli destek
- Ödeme: Paddle (%5 + $0.50/işlem)
- Plan kaynağı: profiles.plan (user-level)
- Kullanıcı sayısı: get_active_user_count() RPC

## Migration Dosyaları (seeds/)
- `migration_contacts.sql` — customers+suppliers → contacts birleşimi
- `migration_user_plan.sql` — plan profiles tablosuna taşıma + get_active_user_count
- `migration_invoice_limit.sql` — get_monthly_invoice_count fonksiyonu
- `migration_permissions.sql` — user_permissions + get_default_permissions
- `fix_company_users_rls.sql` — get_my_company_ids SECURITY DEFINER
- `fix_company_users_insert_rls.sql` — get_my_admin_company_ids INSERT policy
- `fix_company_plans.sql` — 'pro' → 'professional' normalizasyonu

## Solvenin Roadmap

### Şu An (Devam Eden)
- Core ERP modülleri tamamlandı
- POS modülü tamamlandı
- Partner programı sayfası tamamlandı
- Fatura PDF iyileştirme devam ediyor
- Paddle entegrasyonu bekliyor
- Email sistemi bekliyor

### Yakın Vadeli
- İhracat & İthalat modülü (ticari fatura, gümrük beyannamesi, konşimento, menşei şehadetnamesi, gıda/bitki sağlık sertifikası, CMR, TIR karnet — faturaya bağlı, müşteriye email)
- Kasa oturumu & gün sonu raporu
- POS terminal entegrasyonu (Kaspi QR, IP tabanlı POS cihazları)
- Dil audit (10 dil tam tamamlama: EN, TR, RU, KZ, DE, FR, ES, PL, AR, ZH)

### Orta Vadeli
- E-Ticaret modülü (Add-on: $35/ay B2C, $35/ay B2B)
  * 10 hazır şablon
  * Subdomain: musteri.solvenin.com veya kendi domaini (dahil)
  * Yerel ödeme sistemleri (Kaspi QR, Halyk — KZ; iyzico, PayTR — TR; vb.)
  * Kargo: pkge.net API (Jet Logistics KZ, Kazpost, Yurtiçi, DHL vb. 850+ firma)
  * Ürün başına: 4-5 resim + 1 video, meta başlık/açıklama, e-ticaret işareti
  * B2B: Bayi başvuru formu → onay → özel fiyat/vade
  * Stok kartında perakende + toptan fiyat kolonları
  * Stok tükenince listeden kaldır
- Bildirim sistemi (kullanıcı seçer: email / WhatsApp / uygulama içi)
- 2FA (iki faktörlü kimlik doğrulama)

### Uzun Vadeli
- Mobil uygulama (iOS/Android)
- Müşteriye özel white-label uygulama
- App Store (partner modülleri)
- API & Webhooks (Pro plan)

## Pazar Stratejisi
- Aşama 1: Kazakistan + Orta Asya (öncelikli)
- Aşama 2: Türkiye
- Aşama 3: Global

## E-Ticaret Teknik Notlar
- order_type: 'ecommerce' (sales_orders tablosunda)
- Ürün tablosunda: is_ecommerce boolean, retail_price, wholesale_price, meta_title, meta_description
- Subdomain: Vercel custom domain ile yönetilir
- Ödeme: her ülke için ayrı entegrasyon, Settings'ten API key girilir
- Kargo: pkge.net API anahtarı Settings'ten girilir
