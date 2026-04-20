-- 062_tx_contact_id.sql
-- Add contact_id FK to cash_transactions and bank_transactions
-- for linking transactions to contacts (cari hesap).

BEGIN;

ALTER TABLE cash_transactions
  ADD COLUMN IF NOT EXISTS contact_id UUID REFERENCES contacts(id),
  ADD COLUMN IF NOT EXISTS counterparty VARCHAR(200);

ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS contact_id UUID REFERENCES contacts(id);

INSERT INTO migrations_log (file_name, notes)
VALUES ('062_tx_contact_id.sql',
  'contact_id + counterparty on cash/bank transactions for cari linking')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
