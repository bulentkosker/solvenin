-- ============================================================
-- M072: cash/bank tx — category-driven fields + transfer RPC
-- ============================================================
-- The Add/Edit modal gains category-driven conditional sections:
-- salary/advance (employee_id), transfer (target register/bank + group).
-- No CHECK constraint on category column — legacy values (sale,
-- purchase, expense, fee) must keep working alongside the new enum.
-- Transfers land atomically through execute_cash_bank_transfer: two
-- insert statements, one transaction, or full rollback.
-- ============================================================

BEGIN;

-- ─── 1. Additive columns ─────────────────────────────────────
ALTER TABLE cash_transactions
  ADD COLUMN IF NOT EXISTS employee_id UUID REFERENCES employees(id),
  ADD COLUMN IF NOT EXISTS transfer_target_register_id UUID REFERENCES cash_registers(id),
  ADD COLUMN IF NOT EXISTS transfer_target_bank_id UUID REFERENCES bank_accounts(id),
  ADD COLUMN IF NOT EXISTS transfer_group_id UUID;

ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS employee_id UUID REFERENCES employees(id),
  ADD COLUMN IF NOT EXISTS transfer_target_register_id UUID REFERENCES cash_registers(id),
  ADD COLUMN IF NOT EXISTS transfer_target_bank_id UUID REFERENCES bank_accounts(id),
  ADD COLUMN IF NOT EXISTS transfer_group_id UUID;

CREATE INDEX IF NOT EXISTS idx_cash_tx_employee
  ON cash_transactions(employee_id) WHERE employee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cash_tx_transfer_group
  ON cash_transactions(transfer_group_id) WHERE transfer_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_tx_employee
  ON bank_transactions(employee_id) WHERE employee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_tx_transfer_group
  ON bank_transactions(transfer_group_id) WHERE transfer_group_id IS NOT NULL;

-- cash_transactions.source_type CHECK currently omits 'own_transfer'
-- (bank_transactions got it in M058). Transfer RPC needs the same value
-- on both tables. Widen the CHECK — old values stay allowed.
ALTER TABLE cash_transactions DROP CONSTRAINT IF EXISTS chk_cash_source_type;
ALTER TABLE cash_transactions ADD CONSTRAINT chk_cash_source_type
  CHECK (source_type IN ('sales_order','purchase_order','payment','manual','opening','transfer','own_transfer','bank_import'));

-- ─── 2. RPC — atomic two-sided transfer ─────────────────────
-- Inputs:
--   p_group_id      client-generated UUID (both sides share it)
--   p_company_id    company owner
--   p_source_type   'cash' | 'bank'
--   p_source_id     cash_register.id or bank_account.id
--   p_target_type   'cash' | 'bank'
--   p_target_id     cash_register.id or bank_account.id
--   p_amount        > 0
--   p_date          transaction_date
--   p_description   NOT NULL
--   p_reference     nullable
--
-- Both sides use source_type='own_transfer' so the existing
-- bank_transactions CHECK (added in M058) is satisfied, and the pair
-- is filterable. Each row points back to the OTHER side via
-- transfer_target_register_id / transfer_target_bank_id so a UI can
-- navigate between them without chasing transfer_group_id separately.

CREATE OR REPLACE FUNCTION public.execute_cash_bank_transfer(
  p_group_id     uuid,
  p_company_id   uuid,
  p_source_type  text,
  p_source_id    uuid,
  p_target_type  text,
  p_target_id    uuid,
  p_amount       numeric,
  p_date         date,
  p_description  text,
  p_reference    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_src_currency text;
  v_tgt_currency text;
  v_source_row_id uuid;
  v_target_row_id uuid;
BEGIN
  IF p_source_type NOT IN ('cash','bank') THEN RAISE EXCEPTION 'source_type must be cash or bank'; END IF;
  IF p_target_type NOT IN ('cash','bank') THEN RAISE EXCEPTION 'target_type must be cash or bank'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'amount must be > 0'; END IF;
  IF p_source_type = p_target_type AND p_source_id = p_target_id THEN
    RAISE EXCEPTION 'source and target accounts must differ';
  END IF;
  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'description required';
  END IF;

  -- Authorization (service role bypasses by NULL auth.uid())
  IF auth.uid() IS NOT NULL AND NOT (p_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Fetch + validate both accounts belong to the company
  IF p_source_type = 'cash' THEN
    SELECT currency_code INTO v_src_currency FROM cash_registers
      WHERE id = p_source_id AND company_id = p_company_id AND deleted_at IS NULL;
  ELSE
    SELECT currency_code INTO v_src_currency FROM bank_accounts
      WHERE id = p_source_id AND company_id = p_company_id AND deleted_at IS NULL;
  END IF;
  IF v_src_currency IS NULL THEN RAISE EXCEPTION 'source account not found for company'; END IF;

  IF p_target_type = 'cash' THEN
    SELECT currency_code INTO v_tgt_currency FROM cash_registers
      WHERE id = p_target_id AND company_id = p_company_id AND deleted_at IS NULL;
  ELSE
    SELECT currency_code INTO v_tgt_currency FROM bank_accounts
      WHERE id = p_target_id AND company_id = p_company_id AND deleted_at IS NULL;
  END IF;
  IF v_tgt_currency IS NULL THEN RAISE EXCEPTION 'target account not found for company'; END IF;

  -- ── Source (out) ───────────────────────────────────────
  IF p_source_type = 'cash' THEN
    INSERT INTO cash_transactions (
      company_id, register_id, type, amount, currency_code,
      description, category, reference, transaction_date, source_type,
      transfer_target_register_id, transfer_target_bank_id, transfer_group_id,
      created_by
    ) VALUES (
      p_company_id, p_source_id, 'out', p_amount, v_src_currency,
      p_description, 'transfer_out', p_reference, p_date, 'own_transfer',
      CASE WHEN p_target_type='cash' THEN p_target_id END,
      CASE WHEN p_target_type='bank' THEN p_target_id END,
      p_group_id, auth.uid()
    ) RETURNING id INTO v_source_row_id;
  ELSE
    INSERT INTO bank_transactions (
      company_id, account_id, type, amount, currency_code,
      description, category, reference, transaction_date, source_type,
      transfer_target_register_id, transfer_target_bank_id, transfer_group_id,
      created_by
    ) VALUES (
      p_company_id, p_source_id, 'out', p_amount, v_src_currency,
      LEFT(p_description, 255), 'transfer_out', LEFT(p_reference, 100), p_date, 'own_transfer',
      CASE WHEN p_target_type='cash' THEN p_target_id END,
      CASE WHEN p_target_type='bank' THEN p_target_id END,
      p_group_id, auth.uid()
    ) RETURNING id INTO v_source_row_id;
  END IF;

  -- ── Target (in) — back-refs point at the source ───────
  IF p_target_type = 'cash' THEN
    INSERT INTO cash_transactions (
      company_id, register_id, type, amount, currency_code,
      description, category, reference, transaction_date, source_type,
      transfer_target_register_id, transfer_target_bank_id, transfer_group_id,
      created_by
    ) VALUES (
      p_company_id, p_target_id, 'in', p_amount, v_tgt_currency,
      p_description, 'transfer_in', p_reference, p_date, 'own_transfer',
      CASE WHEN p_source_type='cash' THEN p_source_id END,
      CASE WHEN p_source_type='bank' THEN p_source_id END,
      p_group_id, auth.uid()
    ) RETURNING id INTO v_target_row_id;
  ELSE
    INSERT INTO bank_transactions (
      company_id, account_id, type, amount, currency_code,
      description, category, reference, transaction_date, source_type,
      transfer_target_register_id, transfer_target_bank_id, transfer_group_id,
      created_by
    ) VALUES (
      p_company_id, p_target_id, 'in', p_amount, v_tgt_currency,
      LEFT(p_description, 255), 'transfer_in', LEFT(p_reference, 100), p_date, 'own_transfer',
      CASE WHEN p_source_type='cash' THEN p_source_id END,
      CASE WHEN p_source_type='bank' THEN p_source_id END,
      p_group_id, auth.uid()
    ) RETURNING id INTO v_target_row_id;
  END IF;

  RETURN jsonb_build_object(
    'success',       true,
    'group_id',      p_group_id,
    'source_row_id', v_source_row_id,
    'source_type',   p_source_type,
    'target_row_id', v_target_row_id,
    'target_type',   p_target_type
  );
END;
$$;

REVOKE ALL ON FUNCTION public.execute_cash_bank_transfer(uuid,uuid,text,uuid,text,uuid,numeric,date,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.execute_cash_bank_transfer(uuid,uuid,text,uuid,text,uuid,numeric,date,text,text) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('072_cash_bank_tx_extra_fields.sql',
  'cash/bank_transactions: employee_id, transfer_target_register_id, transfer_target_bank_id, transfer_group_id + execute_cash_bank_transfer RPC (atomic 2-sided insert).');

COMMIT;
