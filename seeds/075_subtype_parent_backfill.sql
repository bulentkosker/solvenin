-- ============================================================
-- M075: subtype — parent'tan miras al + backfill
-- ============================================================
-- Yeni hesap açılırken saveAccount (accounting.html) artık user
-- subtype seçmediyse parent'tan miras alıyor. Bu migration, daha önce
-- yanlış veya manuel seçilmiş child hesapları parent ile hizalar.
--
-- Koşul: sadece parent subtype dolu VE child subtype parent'tan farklı
-- olanlar hizalanır. Parent subtype NULL ise child aynen kalır.
-- ============================================================

BEGIN;

WITH fixes AS (
  UPDATE chart_of_accounts c
  SET subtype = p.subtype,
      updated_at = NOW()
  FROM chart_of_accounts p
  WHERE c.parent_id = p.id
    AND c.deleted_at IS NULL
    AND p.deleted_at IS NULL
    AND p.subtype IS NOT NULL
    AND c.subtype IS DISTINCT FROM p.subtype
  RETURNING c.id
)
INSERT INTO migrations_log (file_name, notes)
SELECT '075_subtype_parent_backfill.sql',
  format('Subtype inheritance backfill — %s child rows aligned to parent subtype', COUNT(*))
FROM fixes;

-- If zero rows matched, still log the migration.
INSERT INTO migrations_log (file_name, notes)
SELECT '075_subtype_parent_backfill.sql',
  'Subtype inheritance backfill — 0 rows needed fixing (no parents with non-null subtype had divergent children)'
WHERE NOT EXISTS (SELECT 1 FROM migrations_log WHERE file_name = '075_subtype_parent_backfill.sql');

COMMIT;
