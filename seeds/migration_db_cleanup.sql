-- Solvenin Database Cleanup
-- Created: 2026-04-04
-- Removes unused tables (8) and columns (3) per audit report

-- Unused tables (all empty, no code references)
DROP TABLE IF EXISTS localization_accounts CASCADE;
DROP TABLE IF EXISTS invitations CASCADE;
DROP TABLE IF EXISTS equipment_categories CASCADE;
DROP TABLE IF EXISTS project_files CASCADE;
DROP TABLE IF EXISTS project_members CASCADE;
DROP TABLE IF EXISTS task_comments CASCADE;
DROP TABLE IF EXISTS task_groups CASCADE;
DROP TABLE IF EXISTS deleted_records CASCADE;

-- Unused product columns (pos_quick_buttons table used instead)
ALTER TABLE products DROP COLUMN IF EXISTS pos_quick_button;
ALTER TABLE products DROP COLUMN IF EXISTS pos_button_color;
ALTER TABLE products DROP COLUMN IF EXISTS pos_button_order;

-- Kept for future use:
-- products.image_url (e-commerce product images)
-- products.location (warehouse location)
-- companies.slug (subdomain for e-commerce)
-- companies.max_users (plan user limits)
-- companies.logo_url (invoice/POS branding)
