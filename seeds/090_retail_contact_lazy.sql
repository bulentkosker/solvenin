-- ============================================================
-- M090: Retail contact lazy — trigger drop + per-company cleanup
-- ============================================================
-- M078 her yeni şirkete otomatik "Perakende Satışlar" sistem contact'ı
-- oluşturuyordu (companies AFTER INSERT trigger). 7 şirketin sadece 1'i
-- POS kullanıyor (ANKA), 6 şirkette gereksiz cari kaydı var, kullanıcıyı
-- kafa karıştırıyor.
--
-- Yeni model: lazy creation. POS satışı yapılırken retail contact yoksa
-- pos.html runtime tarafında oluşturulur. companies INSERT trigger
-- kaldırılır.
--
-- Cleanup: POS satışı OLMAYAN şirketlerden retail system contact'ı
-- soft-delete. POS satışı bulunan şirkette (ANKA) dokunulmaz.
-- Soft-delete: pattern olarak deleted_at = now(), is_active = false.
-- Hard-delete tercih edilmedi → cari ekstre/iz audit'i için iz kalır.
-- ============================================================

-- ─── 1. Trigger + function kaldır ────────────────────────
DROP TRIGGER IF EXISTS trg_company_system_contacts ON public.companies;
DROP FUNCTION IF EXISTS public.create_system_contacts_for_company();

-- ─── 2. POS satışı olmayan şirketlerin retail contact'ını sil ──
-- POS satışı = sales_orders.order_type='pos' AND deleted_at IS NULL
WITH companies_with_pos AS (
  SELECT DISTINCT company_id
  FROM public.sales_orders
  WHERE order_type = 'pos' AND deleted_at IS NULL
)
UPDATE public.contacts
   SET is_active = false,
       deleted_at = NOW()
 WHERE is_system = true
   AND name = 'Perakende Satışlar'
   AND deleted_at IS NULL
   AND company_id NOT IN (SELECT company_id FROM companies_with_pos);

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('090_retail_contact_lazy.sql',
  'companies AFTER INSERT trigger trg_company_system_contacts kaldırıldı + POS satışı olmayan şirketlerin Perakende Satışlar sistem contact''ı soft-delete edildi. POS yapan şirkette (ANKA) dokunulmadı. Yeni şirketler ilk POS satışında runtime-create eder (pos.html lazy resolve).')
ON CONFLICT (file_name) DO NOTHING;
