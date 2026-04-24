-- ============================================================
-- M082: was_invoiced flag — sales_orders + purchase_orders
-- ============================================================
-- Problem: Fatura iptali ve sipariş iptali arasında ayrım yoktu.
-- Her ikisi de status='cancelled' oluyordu, ama UI'da "Faturalar"
-- ve "Siparişler" sekmeleri status'e göre filtreliyordu. Sonuç:
-- iptal edilmiş fatura "Siparişler" sekmesine düşüyordu.
--
-- Çözüm: was_invoiced boolean kolonu. Kayıt bir kez 'invoiced'
-- veya 'paid' statüsüne gelirse bu flag true olur; asla false'a
-- dönmez. İptal edildiğinde flag korunur, UI filtresi bu sayede
-- "bu cancelled eskiden fatura mıydı" sorusunu yanıtlar.
--
-- Backfill: şu an invoiced/paid olan tüm rowlar → true. Mevcut
-- cancelled rowlar için history yok, default false kalır (o
-- kayıtlar büyük ihtimalle sipariş iptalidir — kullanıcı tek tek
-- düzeltebilir).
-- ============================================================

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS was_invoiced boolean NOT NULL DEFAULT false;

ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS was_invoiced boolean NOT NULL DEFAULT false;

-- Backfill from current status
UPDATE public.sales_orders
   SET was_invoiced = true
 WHERE status IN ('invoiced', 'paid')
   AND was_invoiced = false;

UPDATE public.purchase_orders
   SET was_invoiced = true
 WHERE status IN ('invoiced', 'paid')
   AND was_invoiced = false;

-- Index for filter queries (partial — only useful rows)
CREATE INDEX IF NOT EXISTS idx_sales_orders_was_invoiced
  ON public.sales_orders (company_id, was_invoiced)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_purchase_orders_was_invoiced
  ON public.purchase_orders (company_id, was_invoiced)
  WHERE is_active = true;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('082_was_invoiced_column.sql',
  'Added was_invoiced boolean to sales_orders + purchase_orders. Backfilled from status IN (invoiced, paid). Solves cancelled-invoice-falling-into-orders-tab bug by preserving invoice history across cancellation. Index on (company_id, was_invoiced) partial is_active=true.')
ON CONFLICT (file_name) DO NOTHING;
