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
- `utils.js` — Global yardımcı fonksiyonlar (fmtNum, parseNum, fmt, fmtShort)
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

## Gelecek Planlar (Roadmap)
- Web sitesi builder + E-ticaret modülü:
  Müşteriler ERP'den kendi web sitelerini oluşturabilsin
  E-ticaret siparişleri direkt ERP'ye düşsün
  Stok, fatura, cari entegre çalışsın
- Partner/Reseller ağı: Her ülkede satış+destek elemanı, gelir paylaşımı
- API & Webhooks (Pro plan için)
- Add-on: Telefon destek ($49/mo), Dedicated Manager ($99/mo), Kurulum ($199)
- App Store: İleride ecosystem büyüyünce
