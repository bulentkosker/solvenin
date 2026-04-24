-- ============================================================
-- M085: sp_companies RPC — doğru ürün/fatura sayıları
-- ============================================================
-- Bug: Servis paneli "Şirketler" listesi yanlış STOK + FAT gösteriyordu.
--
-- Kök nedenler:
--  STOK kolonu: stock_count = stock_movements sayısıydı. Ürünü olan
--   ama henüz stok hareketi olmayan şirketlerde 0 görünüyordu.
--   (KATRE ATLAS: 72 ürün, 0 movement → panel 0 gösteriyordu.)
--   Kullanıcı ürün sayısı bekliyor.
--  FAT kolonu: sadece sales_orders sayılıyordu, purchase_orders eksikti.
--   Ayrıca status IN ('invoiced','paid','overdue') — 'overdue'
--   DB status'ünde constraint'li değil (UI-level kavram), mevcut
--   'overdue' rowları eski kayıtlar — count'a tutarsızlık katıyordu.
--   (ANKA GROUP: 37 sales + 14 purchase = 51 beklenirdi, panel 42.)
--
-- Fix:
--  • Yeni alan product_count = COUNT(products WHERE deleted_at IS NULL)
--    Frontend "STOK" kolonu bu alanı gösterecek. stock_count eski
--    anlamını koruyor (drawer "STOK HAR." için movements sayısı).
--  • invoice_count = (sales_orders + purchase_orders) WHERE status
--    IN ('invoiced','paid') AND is_active=true.
--  • user_count değişmedi (company_users hepsi).
-- ============================================================

DROP FUNCTION IF EXISTS sp_companies();

CREATE OR REPLACE FUNCTION sp_companies() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(c) ORDER BY c.created_at DESC), '[]'::json) FROM (
  SELECT c.id, c.name, c.country_code, c.plan, c.created_at, c.is_frozen, c.freeze_reason, c.logo_url,
    (SELECT COUNT(*) FROM company_users cu WHERE cu.company_id = c.id) AS user_count,
    (
      (SELECT COUNT(*) FROM sales_orders so
        WHERE so.company_id = c.id
          AND so.status IN ('invoiced','paid')
          AND so.is_active = true)
    + (SELECT COUNT(*) FROM purchase_orders po
        WHERE po.company_id = c.id
          AND po.status IN ('invoiced','paid')
          AND po.is_active = true)
    ) AS invoice_count,
    (SELECT COUNT(*) FROM products p
      WHERE p.company_id = c.id
        AND p.deleted_at IS NULL) AS product_count,
    (SELECT COUNT(*) FROM stock_movements sm
      WHERE sm.company_id = c.id AND sm.is_active = true) AS stock_count,
    (SELECT spu.name FROM service_panel_users spu WHERE spu.id = c.partner_id) AS partner_name
  FROM companies c
) c;
$BODY$;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('085_sp_companies_counts_fix.sql',
  'sp_companies: product_count (yeni) = active products; invoice_count artık sales+purchase toplamı (overdue status kaldırıldı); stock_count aynı kalır (drawer STOK HAR için movements).')
ON CONFLICT (file_name) DO NOTHING;
