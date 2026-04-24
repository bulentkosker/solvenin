-- ============================================================
-- M083: delete_order_with_cascade → recompute products.quantity
-- ============================================================
-- Bug: 079'da tanımlanan cascade-delete RPC stock_movements'i
-- soft-delete ediyordu ama products.quantity'yi güncellemiyordu.
-- Sonuç: fatura silinse bile ürün listesinde eski "Stokta Var"
-- değeri görünüyordu.
--
-- Kök neden teşhisi: stock_movements üzerinde trigger YOK
-- (pg_trigger, information_schema.triggers sıfır kayıt). Yine de
-- bir yerde quantity otomatik artıyor (muhtemelen başka bir RPC
-- path). Hangi mekanizma olursa olsun, silme sonrası aktif
-- hareketlerden recompute etmek doğru sonucu garanti eder.
--
-- Değişiklik: 079'un mantığı AYNEN korundu; step 4 (stock_movements
-- soft-delete) sonrasına "etkilenen ürünlerin quantity'sini aktif
-- hareketlerden yeniden hesapla" adımı eklendi. Return JSON'a
-- 'products_recomputed' sayısı eklendi.
--
-- Recompute formülü:
--   quantity = SUM(CASE type='in' THEN qty ELSE -qty END)
--   FROM stock_movements
--   WHERE product_id = ... AND is_active=true AND deleted_at IS NULL
--
-- Etkilenen ürünler: bu order_id üzerine bağlı stock_movements'
-- tüm distinct product_id'leri (soft-delete sonrası da sorgu
-- yapılabilir — deleted_at filtresi yok).
-- ============================================================

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
  v_products_recomputed   int := 0;
BEGIN
  -- ─── Validations ───────────────────────────────────────
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

  -- ─── 1. Tx rows hanging off payments tied to this order ────
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

  -- ─── 3. Direct order-linked tx (POS, auto-bound sale rows) ──
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
  -- Bu order'a bağlı tüm stock_movements distinct product_id'leri
  -- üzerinden. Soft-delete sonrası da bu sorgu çalışır çünkü
  -- movement row'u tabloda kalır (sadece is_active=false olur).
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
      'products_recomputed',   v_products_recomputed
    ),
    'total', v_payment_count + v_bank_payment_count + v_cash_payment_count
           + v_journal_payment_count + v_bank_direct_count + v_cash_direct_count
           + v_journal_direct_count + v_movement_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_with_cascade(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_order_with_cascade(uuid, text) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('083_cascade_delete_recompute_quantity.sql',
  'delete_order_with_cascade RPC: step 4b — affected products.quantity''yi aktif stock_movements''ten yeniden hesapla. 079 mantığı aynen; eski bug: fatura silinse de ürünün quantity''si düşmüyordu.')
ON CONFLICT (file_name) DO NOTHING;
