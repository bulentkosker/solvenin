-- 056_contact_balance_fix.sql
-- Per-contact balance adjustment function for service panel cari repair.

BEGIN;

CREATE OR REPLACE FUNCTION sp_fix_contact_balance(p_company_id uuid, p_contact_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  bal numeric;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN type='debit' THEN amount ELSE -amount END), 0) INTO bal
  FROM contact_transactions WHERE company_id = p_company_id AND contact_id = p_contact_id AND is_active = true;

  IF bal = 0 THEN RETURN json_build_object('ok', true, 'adjusted', 0); END IF;

  INSERT INTO contact_transactions (company_id, contact_id, type, amount, date, description, notes, created_by, is_active)
  VALUES (
    p_company_id, p_contact_id,
    CASE WHEN bal < 0 THEN 'debit' ELSE 'credit' END,
    ABS(bal), CURRENT_DATE,
    'Bakiye düzeltme',
    'Cari Onarımı — Servis Paneli',
    owner_uid, true
  );

  RETURN json_build_object('ok', true, 'adjusted', bal);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('056_contact_balance_fix.sql',
  'sp_fix_contact_balance RPC for per-contact balance adjustment')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
