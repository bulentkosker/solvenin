-- ============================================================
-- M087: execute_currency_conversion RPC + exchange_rate column
-- ============================================================
-- Banka hesapları arası döviz konvertasyonu için atomic RPC.
-- 072'nin (execute_cash_bank_transfer) pattern'i ile aynı —
-- iki bank_transactions row (out/in) tek transfer_group_id'de
-- bağlanır. Fark: kaynak ve hedef tutarlar farklı (her iki
-- hesabın kendi para biriminde) ve kur saklanır.
--
-- Kullanım senaryoları:
--   • USD alış: KZT bankasından out, USD bankasına in, kur 480
--   • USD satış: USD bankasından out, KZT bankasına in, kur 478
--
-- Kategori: conversion_out (kaynak) / conversion_in (hedef).
-- Bunlar mevcut transfer_out/in'den ayrı — UI listede ve
-- raporlarda farklı etiketle görünür.
--
-- Tolerans: target_amount ≈ source_amount × rate olmalı
-- (round-trip tolerance %1 — kullanıcı bilerek farklı tutar
-- girmiş olabilir, ör. komisyon kesintisi). RPC sadece
-- pozitiflik ve farklı hesap kontrolü yapar; tutar/kur
-- ilişkisini frontend hesaplar.
--
-- transfer_target_bank_id back-ref ile sıralı sayfalama ve
-- merge/iptal flow'u 072'deki ile aynı şekilde çalışır.
-- ============================================================

-- ─── 1. exchange_rate kolonu ───────────────────────────
-- Sadece konvertasyon row'larında dolu; normal tx'lerde NULL.
ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS exchange_rate numeric(15, 6);

-- ─── 2. RPC ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.execute_currency_conversion(
  p_company_id      uuid,
  p_source_bank_id  uuid,
  p_target_bank_id  uuid,
  p_source_amount   numeric,
  p_target_amount   numeric,
  p_exchange_rate   numeric,
  p_transaction_date date,
  p_description     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_src_currency  text;
  v_tgt_currency  text;
  v_group_id      uuid := gen_random_uuid();
  v_source_row_id uuid;
  v_target_row_id uuid;
  v_desc          text;
BEGIN
  -- ─── Validations ─────────────────────────────────────
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id required'; END IF;
  IF p_source_bank_id IS NULL OR p_target_bank_id IS NULL THEN
    RAISE EXCEPTION 'source and target bank ids required';
  END IF;
  IF p_source_bank_id = p_target_bank_id THEN
    RAISE EXCEPTION 'source and target accounts must differ';
  END IF;
  IF p_source_amount IS NULL OR p_source_amount <= 0 THEN
    RAISE EXCEPTION 'source_amount must be > 0';
  END IF;
  IF p_target_amount IS NULL OR p_target_amount <= 0 THEN
    RAISE EXCEPTION 'target_amount must be > 0';
  END IF;
  IF p_exchange_rate IS NULL OR p_exchange_rate <= 0 THEN
    RAISE EXCEPTION 'exchange_rate must be > 0';
  END IF;
  IF p_transaction_date IS NULL THEN
    RAISE EXCEPTION 'transaction_date required';
  END IF;

  -- Authorization (service role bypasses by NULL auth.uid())
  IF auth.uid() IS NOT NULL AND NOT (p_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate both accounts belong to this company + are active
  SELECT currency_code INTO v_src_currency FROM bank_accounts
    WHERE id = p_source_bank_id AND company_id = p_company_id AND deleted_at IS NULL;
  IF v_src_currency IS NULL THEN
    RAISE EXCEPTION 'source bank account not found for company';
  END IF;

  SELECT currency_code INTO v_tgt_currency FROM bank_accounts
    WHERE id = p_target_bank_id AND company_id = p_company_id AND deleted_at IS NULL;
  IF v_tgt_currency IS NULL THEN
    RAISE EXCEPTION 'target bank account not found for company';
  END IF;

  -- Currency must differ — same-currency transfers should use
  -- execute_cash_bank_transfer (kategori transfer_out/in) instead.
  IF v_src_currency = v_tgt_currency THEN
    RAISE EXCEPTION 'currency conversion requires different currencies (% = %). Use cash/bank transfer for same-currency moves.',
      v_src_currency, v_tgt_currency
      USING ERRCODE = 'check_violation';
  END IF;

  -- Default description if blank
  v_desc := COALESCE(NULLIF(btrim(p_description), ''),
    format('Döviz konvertasyonu: %s %s → %s %s (kur %s)',
      p_source_amount, v_src_currency, p_target_amount, v_tgt_currency, p_exchange_rate));

  -- ─── Source (out) ─────────────────────────────────────
  INSERT INTO bank_transactions (
    company_id, account_id, type, amount, currency_code,
    description, category, transaction_date, source_type,
    transfer_target_bank_id, transfer_group_id, exchange_rate,
    created_by
  ) VALUES (
    p_company_id, p_source_bank_id, 'out', p_source_amount, v_src_currency,
    LEFT(v_desc, 255), 'conversion_out', p_transaction_date, 'own_transfer',
    p_target_bank_id, v_group_id, p_exchange_rate,
    auth.uid()
  ) RETURNING id INTO v_source_row_id;

  -- ─── Target (in) — back-ref to source ─────────────────
  INSERT INTO bank_transactions (
    company_id, account_id, type, amount, currency_code,
    description, category, transaction_date, source_type,
    transfer_target_bank_id, transfer_group_id, exchange_rate,
    created_by
  ) VALUES (
    p_company_id, p_target_bank_id, 'in', p_target_amount, v_tgt_currency,
    LEFT(v_desc, 255), 'conversion_in', p_transaction_date, 'own_transfer',
    p_source_bank_id, v_group_id, p_exchange_rate,
    auth.uid()
  ) RETURNING id INTO v_target_row_id;

  RETURN jsonb_build_object(
    'success', true,
    'transfer_group_id', v_group_id,
    'source_tx_id', v_source_row_id,
    'target_tx_id', v_target_row_id,
    'source_amount', p_source_amount,
    'source_currency', v_src_currency,
    'target_amount', p_target_amount,
    'target_currency', v_tgt_currency,
    'exchange_rate', p_exchange_rate
  );
END;
$$;

REVOKE ALL ON FUNCTION public.execute_currency_conversion(uuid, uuid, uuid, numeric, numeric, numeric, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.execute_currency_conversion(uuid, uuid, uuid, numeric, numeric, numeric, date, text) TO authenticated;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('087_currency_conversion_rpc.sql',
  'execute_currency_conversion RPC: 2 bank_transactions (conversion_out + conversion_in) atomic transfer_group_id ile bağlı. exchange_rate kolonu eklendi (sadece konvertasyon row''larında dolu). Source/target farklı currency zorunlu — aynı currency için execute_cash_bank_transfer kullanılır.')
ON CONFLICT (file_name) DO NOTHING;
