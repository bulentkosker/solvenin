# Kritik Akışlar — Bozulmamalı

## Kasa/Banka Hareketleri (cashbank.html)

**Ana modal:** Add Cash Transaction / Add Bank Transaction

Korunacak davranışlar:
- Tür seçimine göre koşullu alanlar: Gider → hesap+referans, Satış Tahsilatı → cari+referans, Maaş → çalışan+hesap+referans, Avans → çalışan+hesap, Transfer → hedef hesap (kasa/banka arası)
- chart_of_account_id her kayıtta doldurulur
- Cari seçilirse contact_transactions kayıt düşer (bank_transaction_id veya cash_transaction_id FK ile)
- Legacy "category" TEXT kolonu korunur, yeni kayıtlarda chart_of_account type'ından türetilir
- Edit modal'ı Add modal'ının aynısıdır — aynı alan görünürlüğü, aynı dropdown içeriği, aynı validasyon
- Eski kayıtlar (category='expense', 'sale', 'salary') edit açılınca çöp değer göstermez, anlamlı şekilde mapleri

## Hesap Planı (accounting.html)

Korunacak davranışlar:
- User sub-account açarken (örn "632.01") parent_id ve level otomatik hesaplanır
- Type inheritance: user type seçmediyse parent'tan miras alınır
- Soft delete: deleted_at IS NULL filtresi her dropdown'da olmalı
- name_local TR, name EN fallback — dropdown'da name_local kullan
- Bakiyeler cash_transactions + bank_transactions'tan SUM ile hesaplanır
- Natural-side işaret kuralı: asset/expense/cost debit-natural, revenue/liability/equity credit-natural

## Dropdown Filtreleme (gelir/gider hesabı)

Korunacak davranışlar:
- Leaf-only: parent_id set'inde olmayan hesaplar görünür (level'a bağımlı DEĞİL)
- Direction filter: in → revenue, out → expense+cost
- Arama: code ve name_local alanlarında case-insensitive
- Scroll edilebilir (max-height + overflow-y:auto)
- Hem Add hem Edit modal'ında aynı filtre

## Hesap Planı Template → Şirket Yükleme

Korunacak davranışlar:
- chart_of_accounts_templates tablosu TR template'i resmi TDHP (211 hesap)
- Yeni şirket açılınca country_code'a göre template yüklenir
- Mevcut şirket hesapları company_id ile izole (başka şirket etkilenmez)

## Banka Mutabakat / Import (bank-import.html)

Korunacak davranışlar:
- 5 adımlı wizard: history → upload → analysis → preview/match → success
- System template match → AI fallback sırası
- execute_import RPC atomic transaction, rollback garantisi
- import_templates ortak (bank + kasa), target_module CHECK'li

## Cari Ekstresi (contacts)

Korunacak davranışlar:
- contact_transactions her türlü finansal etki için kayıt tutar (fatura, tahsilat, ödeme, banka/kasa)
- bank_transaction_id ve cash_transaction_id FK'ler ile kasa/banka hareketlerine bağlı
- Cari silinirken contact_transactions cascade (veya soft delete)

## Payroll / Bordro (hr.html)

Korunacak davranışlar:
- Tablo kolonları: period_year, period_month (year/month DEĞİL — PGRST 42703 hatası riski)
- Aynı çalışan × aynı period için tek kayıt (unique)

## Modül Yönetimi (company_modules)

Korunacak davranışlar:
- accounting modülü kapalıysa journal_entries oluşturulmaz
- AMA chart_of_accounts her zaman kullanılır (rapor için)
- Sidebar görünürlüğü company_modules.is_active'e bağlı

## Multi-Company / RLS

Korunacak davranışlar:
- Tüm sorgularda company_id filtresi olmalı
- RLS politikası kullanıcıyı kendi şirket verisiyle sınırlandırır
- Soft delete: deleted_at IS NULL her kritik sorguda
