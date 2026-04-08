-- Migration: 004_company_soft_delete
-- Description: Soft delete + 30-day trash + audit log + recovery RPCs
-- Backward Compatible: YES — adds new columns and a new table.
--   Existing companies have deleted_at = NULL so the new RLS policy
--   (which filters deleted_at IS NULL) keeps them visible.
-- Rollback: see seeds/migration_company_soft_delete.sql for full reversal

-- The full body of this migration lives in
-- seeds/migration_company_soft_delete.sql (~270 lines: ALTER companies,
-- create company_audit_log, replace RLS policies, update
-- get_my_companies / get_my_company_ids / cleanup_expired_demos,
-- create soft_delete_company / restore_company /
-- permanently_delete_company / sp_trash_companies /
-- sp_company_audit_log / sp_expired_trash_count).
--
-- This file exists in /migrations as the canonical numbered entry.
-- If you need to re-run, execute seeds/migration_company_soft_delete.sql
-- via the same exec_sql RPC pathway.

INSERT INTO migrations_log (file_name, notes)
VALUES (
  '004_company_soft_delete.sql',
  'Soft delete columns, audit log, RPCs (soft_delete/restore/permanently_delete) and updated RLS'
)
ON CONFLICT (file_name) DO NOTHING;
