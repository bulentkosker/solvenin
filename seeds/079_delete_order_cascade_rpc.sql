-- ============================================================
-- M079: delete_order_with_cascade RPC (accounting-off only)
-- ============================================================
-- Muhasebe entegrasyonu KAPALI şirketlerde kullanıcının faturayı
-- + bağlı ödeme/stok/kasa-banka kayıtlarını tek seferde silmesini
-- sağlar. Muhasebe AÇIK olan şirketlerde RPC reddeder — o akışta
-- hala "cancel" (status=cancelled) veya pre-check'li deleteOrder
-- kullanılacak.
--
-- Pattern: hepsi soft-delete (deleted_at=NOW()). FK'lerde RESTRICT
-- var (payments ↔ bank/cash/journal), ama RESTRICT sadece hard
-- DELETE'te tetiklenir; soft-delete bir UPDATE olduğu için FK
-- ihlali olmaz.
--
-- Taşınan kayıt zinciri:
--   payments (order_id|purchase_order_id = p_order_id)
--   ├─ payments.id'yi referans alan bank_transactions, cash_transactions, journal_entries
--   └─ payments'ın kendisi soft-delete
--   cash/bank_transactions direkt order-linked (sales_order_id / purchase_order_id = p_order_id)
--   journal_entries direkt order-linked
--   stock_movements direkt order-linked (is_active=false + deleted_at)
--   sales_orders / purchase_orders: deleted_at + is_active=false
-- ============================================================

BEGIN;

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

  -- Authorization (service role bypass)
  IF v_uid IS NOT NULL AND NOT (v_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Accounting-off check — this RPC is ONLY for companies with accounting
  -- integration disabled. When enabled, deletion goes through the
  -- existing pre-check path which refuses to run if payments/journal
  -- exist (preserves ledger integrity).
  SELECT COALESCE(accounting_enabled, false) INTO v_accounting_enabled
    FROM companies WHERE id = v_company_id;
  IF v_accounting_enabled THEN
    RAISE EXCEPTION 'Cannot cascade delete when accounting is enabled. Use cancel instead.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- ─── 1. Tx rows hanging off payments tied to this order ────
  -- Soft-delete bank/cash_transactions whose payment_id points to a
  -- payment on this order. We do this BEFORE soft-deleting payments
  -- so the linkage query is unambiguous even though soft-delete
  -- wouldn't change PostgREST visibility of the FK target.
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
      'stock_movements',       v_movement_count
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
VALUES ('079_delete_order_cascade_rpc.sql',
  'delete_order_with_cascade RPC — accounting-off only. Soft-deletes payments + their linked bank/cash/journal entries + direct order-linked tx + stock_movements + the order row itself, atomically. RAISE EXCEPTION when accounting_enabled=true (cancel path remains).');

COMMIT;
