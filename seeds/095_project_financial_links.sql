-- ============================================================
-- M095: project_id columns on sales/purchase/cash/bank tables
-- ============================================================
-- Faz 1 finansal entegrasyon: bir hareket istenirse bir projeye
-- bağlanabilsin. Opsiyonel — boş bırakılan hareketler "genel"
-- sayılır. ON DELETE SET NULL ile proje silinince hareket kalır,
-- sadece ilişki kopar.
--
-- Index'ler partial: sadece NOT NULL olan satırlarda. Listing/
-- summary sorgu pattern'i `WHERE project_id = X AND deleted_at IS NULL`.
-- ============================================================

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES public.projects(id) ON DELETE SET NULL;
ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES public.projects(id) ON DELETE SET NULL;
ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES public.projects(id) ON DELETE SET NULL;
ALTER TABLE public.cash_transactions
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES public.projects(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sales_orders_project
  ON public.sales_orders (project_id)
  WHERE project_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_orders_project
  ON public.purchase_orders (project_id)
  WHERE project_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_bank_transactions_project
  ON public.bank_transactions (project_id)
  WHERE project_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cash_transactions_project
  ON public.cash_transactions (project_id)
  WHERE project_id IS NOT NULL AND deleted_at IS NULL;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('095_project_financial_links.sql',
  'sales_orders, purchase_orders, bank_transactions, cash_transactions tablolarına project_id kolonu eklendi (FK projects(id) ON DELETE SET NULL). 4 partial index (NOT NULL + deleted_at IS NULL filter ile). Faz 1 finansal entegrasyon — proje detay sayfası gelir/gider/net özeti için.')
ON CONFLICT (file_name) DO NOTHING;
