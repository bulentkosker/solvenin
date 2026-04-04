-- Solvenin Legacy Table Cleanup
-- Created: 2026-04-04
-- Removes deprecated tables after data migration to contacts

-- 1. Drop empty stock table
DROP TABLE IF EXISTS stock CASCADE;

-- 2. Migrate projects FK from customers to contacts
ALTER TABLE projects DROP CONSTRAINT IF EXISTS projects_client_id_fkey;
ALTER TABLE projects ADD CONSTRAINT projects_client_id_fkey
  FOREIGN KEY (client_id) REFERENCES contacts(id);

-- 3. Drop legacy tables (data already in contacts table)
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS suppliers CASCADE;

-- Note: customers had 6 rows (3 orphans with company_id=NULL, 3 matched in contacts)
-- Note: suppliers had 4 rows (all matched in contacts)
-- Note: stock had 0 rows (replaced by stock_levels)
