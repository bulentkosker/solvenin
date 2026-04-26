-- ============================================================
-- M088: payroll soft-delete + cancelled status
-- ============================================================
-- payroll tablosu şu an iptal/silme mekanizmasından yoksun:
--   - status CHECK sadece draft/approved/paid kabul ediyor
--   - deleted_at / deleted_by kolonu yok
-- Yanlışlıkla oluşan veya hatalı bordrolar için iptal + soft-delete
-- gerekli. Pattern sales_orders / purchase_orders ile aynı.
--
-- Değişiklik:
--   1) ALTER TABLE: deleted_at + deleted_by + cleanup_at + cleanup_by
--      eklenir (cascade RPC'leri ile uyumlu pattern).
--   2) status CHECK güncellenir → cancelled değeri kabul edilir.
--   3) Partial index: aktif (deleted_at IS NULL) rowlar üzerinde
--      sık kullanılan (company_id, period_year, period_month) sorgusu.
-- ============================================================

ALTER TABLE public.payroll
  ADD COLUMN IF NOT EXISTS deleted_at  timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by  uuid,
  ADD COLUMN IF NOT EXISTS cleanup_at  timestamptz,
  ADD COLUMN IF NOT EXISTS cleanup_by  uuid;

-- status CHECK: 'cancelled' eklendi
ALTER TABLE public.payroll DROP CONSTRAINT IF EXISTS payroll_status_check;
ALTER TABLE public.payroll
  ADD CONSTRAINT payroll_status_check
  CHECK (status IN ('draft','approved','paid','cancelled'));

-- Partial index — listelemede deleted_at IS NULL filter ile birlikte
CREATE INDEX IF NOT EXISTS idx_payroll_active_period
  ON public.payroll (company_id, period_year, period_month)
  WHERE deleted_at IS NULL;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('088_payroll_soft_delete.sql',
  'payroll: deleted_at/deleted_by/cleanup_* kolonları eklendi; status CHECK ''cancelled'' kabul edecek şekilde güncellendi; idx_payroll_active_period partial index. Soft-delete + cancel akışı için altyapı.')
ON CONFLICT (file_name) DO NOTHING;
