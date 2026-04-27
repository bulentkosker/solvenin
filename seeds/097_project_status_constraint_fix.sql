-- ============================================================
-- M097: Fix conflicting projects.status CHECK constraints
-- ============================================================
-- Tablada iki ayrı CHECK var ve farklı set'lere izin veriyor:
--   chk_project_status         → 'active' yasak
--   projects_status_check      → 'in_progress' yasak
-- Form 'active' kullanıyor → save sırasında "Geçersiz değer" hatası.
-- chk_project_status'ı düşürüyoruz; projects_status_check kalıyor
-- (planning/active/on_hold/completed/cancelled set'i). Form bu set ile
-- zaten uyumlu.
-- ============================================================

ALTER TABLE public.projects
  DROP CONSTRAINT IF EXISTS chk_project_status;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('097_project_status_constraint_fix.sql',
  'projects tablosundan chk_project_status CHECK constraint düşürüldü — projects_status_check ile çakışıyordu (active vs in_progress). Frontend formu active kullanıyor; bu constraint formu engelliyordu (Geçersiz değer toast). Ana set: planning/active/on_hold/completed/cancelled.')
ON CONFLICT (file_name) DO NOTHING;
