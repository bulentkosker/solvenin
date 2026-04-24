-- ============================================================
-- M084: cascade delete → order_items + deleted_at column
-- ============================================================
-- Bug: 079/083 stock_movements'i soft-delete ediyor ama
-- sales_order_items + purchase_order_items dokunulmuyor. Sonuç:
-- muhasebe kapalıyken fatura silinse bile order_items tablosunda
-- kayıtlar duruyor → ürünü silmeye çalışınca "ürünün sipariş
-- kalemi var" diyen pre-check takılıyor.
--
-- Teşhis: sales_order_items + purchase_order_items tablolarında
-- `deleted_at` kolonu YOKTU (sadece cleanup_at/cleanup_by vardı).
-- Bu migration deleted_at + deleted_by ekliyor ve RPC'ye step
-- 4c olarak items soft-delete mantığını ekliyor.
--
-- inventory.html confirmDelete pre-check'i `.is('deleted_at',null)`
-- ile filtrelediğinde artık silinmiş order'a bağlı items
-- engelleyici değil.
-- ============================================================

-- ─── 1. Add deleted_at + deleted_by columns ──────────────────
ALTER TABLE public.sales_order_items
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid;

ALTER TABLE public.purchase_order_items
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid;

-- Partial index for pre-check filtering (only non-deleted rows)
CREATE INDEX IF NOT EXISTS idx_sales_order_items_active_product
  ON public.sales_order_items (product_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_order_items_active_product
  ON public.purchase_order_items (product_id)
  WHERE deleted_at IS NULL;

-- ─── 2. Backfill: items whose parent order is soft-deleted ──
-- Legacy data: orders soft-deleted before this migration left
-- their items orphaned (parent deleted_at IS NOT NULL, item
-- deleted_at IS NULL). Mark them consistently.
UPDATE public.sales_order_items i
   SET deleted_at = o.deleted_at,
       deleted_by = o.deleted_by,
       cleanup_at = COALESCE(i.cleanup_at, o.deleted_at)
  FROM public.sales_orders o
 WHERE i.order_id = o.id
   AND o.deleted_at IS NOT NULL
   AND i.deleted_at IS NULL;

UPDATE public.purchase_order_items i
   SET deleted_at = o.deleted_at,
       deleted_by = o.deleted_by,
       cleanup_at = COALESCE(i.cleanup_at, o.deleted_at)
  FROM public.purchase_orders o
 WHERE i.order_id = o.id
   AND o.deleted_at IS NOT NULL
   AND i.deleted_at IS NULL;

-- ─── 3. Rewrite delete_order_with_cascade RPC ────────────────
CREATE OR REPLACE FUNCTION public.delete_order_with_cascade(
  p_order_id uuid,
  p_order_type text  -- 'sale' | 'purchase'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id         uuid;
  v_accounting_enabled boolean;
  v_uid                uuid := auth.uid();
  v_now                timestamptz := NOW();

  v_payment_count         int := 0;
  v_bank_payment_count    int := 0;
  v_cash_payment_count    int := 0;
  v_journal_payment_count int := 0;
  v_bank_direct_count     int := 0;
  v_cash_direct_count     int := 0;
  v_journal_direct_count  int := 0;
  v_movement_count        int := 0;
  v_items_count           int := 0;
  v_products_recomputed   int := 0;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'p_order_id required';
  END IF;
  IF p_order_type NOT IN ('sale', 'purchase') THEN
    RAISE EXCEPTION 'p_order_type must be ''sale'' or ''purchase''';
  END IF;

  IF p_order_type = 'sale' THEN
    SELECT company_id INTO v_company_id FROM sales_orders WHERE id = p_order_id;
    IF v_company_id IS NULL THEN RAISE EXCEPTION 'Sales order not found'; END IF;
  ELSE
    SELECT company_id INTO v_company_id FROM purchase_orders WHERE id = p_order_id;
    IF v_company_id IS NULL THEN RAISE EXCEPTION 'Purchase order not found'; END IF;
  END IF;

  IF v_uid IS NOT NULL AND NOT (v_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT COALESCE(accounting_enabled, false) INTO v_accounting_enabled
    FROM companies WHERE id = v_company_id;
  IF v_accounting_enabled THEN
    RAISE EXCEPTION 'Cannot cascade delete when accounting is enabled. Use cancel instead.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- ─── 1. bank/cash/journal tx tied to this order's payments ────
  IF p_order_type = 'sale' THEN
    UPDATE bank_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_bank_payment_count = ROW_COUNT;

    UPDATE cash_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_cash_payment_count = ROW_COUNT;

    UPDATE journal_entries
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_journal_payment_count = ROW_COUNT;
  ELSE
    UPDATE bank_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE purchase_order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_bank_payment_count = ROW_COUNT;

    UPDATE cash_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE purchase_order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_cash_payment_count = ROW_COUNT;

    UPDATE journal_entries
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE payment_id IN (SELECT id FROM payments WHERE purchase_order_id = p_order_id)
       AND deleted_at IS NULL;
    GET DIAGNOSTICS v_journal_payment_count = ROW_COUNT;
  END IF;

  -- ─── 2. Payments themselves ────────────────────────────
  IF p_order_type = 'sale' THEN
    UPDATE payments
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE order_id = p_order_id AND deleted_at IS NULL;
  ELSE
    UPDATE payments
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE purchase_order_id = p_order_id AND deleted_at IS NULL;
  END IF;
  GET DIAGNOSTICS v_payment_count = ROW_COUNT;

  -- ─── 3. Direct order-linked tx (POS, auto-bound) ──
  IF p_order_type = 'sale' THEN
    UPDATE bank_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE sales_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_bank_direct_count = ROW_COUNT;

    UPDATE cash_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE sales_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_cash_direct_count = ROW_COUNT;

    UPDATE journal_entries
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE sales_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_journal_direct_count = ROW_COUNT;
  ELSE
    UPDATE bank_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE purchase_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_bank_direct_count = ROW_COUNT;

    UPDATE cash_transactions
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE purchase_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_cash_direct_count = ROW_COUNT;

    UPDATE journal_entries
       SET deleted_at = v_now, cleanup_at = v_now, cleanup_by = v_uid
     WHERE purchase_order_id = p_order_id AND deleted_at IS NULL;
    GET DIAGNOSTICS v_journal_direct_count = ROW_COUNT;
  END IF;

  -- ─── 4. Stock movements ─────────────────────────────
  IF p_order_type = 'sale' THEN
    UPDATE stock_movements
       SET is_active = false, deleted_at = v_now, deleted_by = v_uid
     WHERE sales_order_id = p_order_id AND is_active = true;
  ELSE
    UPDATE stock_movements
       SET is_active = false, deleted_at = v_now, deleted_by = v_uid
     WHERE purchase_order_id = p_order_id AND is_active = true;
  END IF;
  GET DIAGNOSTICS v_movement_count = ROW_COUNT;

  -- ─── 4b. Recompute products.quantity from ACTIVE movements ──
  UPDATE products p SET
    quantity = COALESCE((
      SELECT SUM(CASE WHEN sm.type = 'in' THEN sm.quantity ELSE -sm.quantity END)
        FROM stock_movements sm
       WHERE sm.product_id = p.id
         AND sm.is_active = true
         AND sm.deleted_at IS NULL
    ), 0)
  WHERE p.id IN (
    SELECT DISTINCT product_id FROM stock_movements
     WHERE (CASE WHEN p_order_type = 'sale'
                 THEN sales_order_id
                 ELSE purchase_order_id END) = p_order_id
       AND product_id IS NOT NULL
  );
  GET DIAGNOSTICS v_products_recomputed = ROW_COUNT;

  -- ─── 4c. Order items (yeni) ─────────────────────────
  -- deleted_at + deleted_by + cleanup_at + cleanup_by set edilir.
  -- Hard-delete yerine soft-delete tercih edildi: ileride "undo"
  -- ya da "cancelled fatura kalemlerini göster" ihtimali için
  -- kayıt DB'de kalıyor.
  IF p_order_type = 'sale' THEN
    UPDATE sales_order_items
       SET deleted_at = v_now, deleted_by = v_uid,
           cleanup_at = v_now, cleanup_by = v_uid
     WHERE order_id = p_order_id AND deleted_at IS NULL;
  ELSE
    UPDATE purchase_order_items
       SET deleted_at = v_now, deleted_by = v_uid,
           cleanup_at = v_now, cleanup_by = v_uid
     WHERE order_id = p_order_id AND deleted_at IS NULL;
  END IF;
  GET DIAGNOSTICS v_items_count = ROW_COUNT;

  -- ─── 5. The order row itself ────────────────────────
  IF p_order_type = 'sale' THEN
    UPDATE sales_orders
       SET is_active = false, deleted_at = v_now, deleted_by = v_uid
     WHERE id = p_order_id;
  ELSE
    UPDATE purchase_orders
       SET is_active = false, deleted_at = v_now, deleted_by = v_uid
     WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'counts', jsonb_build_object(
      'payments',              v_payment_count,
      'payment_bank_tx',       v_bank_payment_count,
      'payment_cash_tx',       v_cash_payment_count,
      'payment_journal',       v_journal_payment_count,
      'direct_bank_tx',        v_bank_direct_count,
      'direct_cash_tx',        v_cash_direct_count,
      'direct_journal',        v_journal_direct_count,
      'stock_movements',       v_movement_count,
      'order_items',           v_items_count,
      'products_recomputed',   v_products_recomputed
    ),
    'total', v_payment_count + v_bank_payment_count + v_cash_payment_count
           + v_journal_payment_count + v_bank_direct_count + v_cash_direct_count
           + v_journal_direct_count + v_movement_count + v_items_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_with_cascade(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_order_with_cascade(uuid, text) TO authenticated;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('084_cascade_delete_order_items.sql',
  'Added deleted_at + deleted_by to sales_order_items + purchase_order_items. delete_order_with_cascade now soft-deletes order items (step 4c). Backfilled legacy items whose parent order was soft-deleted. Partial indexes on (product_id) WHERE deleted_at IS NULL for fast pre-check.')
ON CONFLICT (file_name) DO NOTHING;
