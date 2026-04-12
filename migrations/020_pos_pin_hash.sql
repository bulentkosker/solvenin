-- ============================================================
-- Migration 020: Hash POS PINs (plain text → SHA256)
-- ============================================================

-- Step 1: Enable pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Step 2: Widen column to fit SHA256 hex (64 chars)
ALTER TABLE company_users ALTER COLUMN pos_pin TYPE varchar(64);

-- Step 3: Hash existing plain text PINs
UPDATE company_users
SET pos_pin = encode(digest(pos_pin, 'sha256'), 'hex')
WHERE pos_pin IS NOT NULL
  AND length(pos_pin) = 4
  AND pos_pin ~ '^\d{4}$';

-- Step 3: Constraint — hashed PIN is always 64 chars
DO $$ BEGIN
  ALTER TABLE company_users
    ADD CONSTRAINT chk_pos_pin_format
      CHECK (pos_pin IS NULL OR length(pos_pin) = 64);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Step 4: PIN verification RPC
CREATE OR REPLACE FUNCTION verify_pos_pin(
  p_company_id uuid,
  p_pin text
)
RETURNS TABLE(user_id uuid, role text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  input_hash text;
BEGIN
  input_hash := encode(digest(p_pin, 'sha256'), 'hex');

  RETURN QUERY
  SELECT cu.user_id, cu.role
  FROM company_users cu
  WHERE cu.company_id = p_company_id
    AND cu.pos_pin = input_hash
    AND cu.role IN ('owner', 'admin', 'manager');
END;
$$;

-- Step 5: PIN set RPC
CREATE OR REPLACE FUNCTION set_pos_pin(
  p_company_id uuid,
  p_user_id uuid,
  p_pin text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_pin IS NULL OR p_pin = '' THEN
    UPDATE company_users
    SET pos_pin = NULL
    WHERE company_id = p_company_id AND user_id = p_user_id;
    RETURN;
  END IF;

  IF p_pin !~ '^\d{4}$' THEN
    RAISE EXCEPTION 'PIN must be exactly 4 digits';
  END IF;

  UPDATE company_users
  SET pos_pin = encode(digest(p_pin, 'sha256'), 'hex')
  WHERE company_id = p_company_id AND user_id = p_user_id;
END;
$$;

-- Step 6: migrations_log
INSERT INTO migrations_log (file_name, notes)
VALUES ('020_pos_pin_hash.sql',
  'Hash POS PINs with SHA256, add verify_pos_pin and set_pos_pin RPC functions')
ON CONFLICT (file_name) DO NOTHING;
