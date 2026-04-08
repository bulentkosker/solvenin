-- Migration: 001_initial_schema
-- Description: Snapshot pointer to the initial Solvenin schema
-- Backward Compatible: YES (this is a no-op marker for the audit log)
-- Rollback: NONE — initial schema cannot be rolled back

-- The actual initial schema lives in /seeds (companies, profiles,
-- company_users, products, contacts, sales_orders, purchase_orders,
-- payments, chart_of_accounts, tax_rates, warehouses, stock_movements,
-- categories, etc.). This file exists as the first row in
-- migrations_log so the numbered ladder starts cleanly.

INSERT INTO migrations_log (file_name, notes)
VALUES ('001_initial_schema.sql', 'Initial schema snapshot pointer')
ON CONFLICT (file_name) DO NOTHING;
