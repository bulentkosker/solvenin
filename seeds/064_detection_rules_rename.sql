-- ============================================================
-- M064: Rename detection_rules.bank_identifier → bank_identifier_pattern
-- ============================================================
-- Browser findMatchingTemplate artık sadece detection_rules kullanıyor
-- (bank_identifier kolonu fallback'i kaldırıldı). Tutarlı bir isim için
-- detection_rules içindeki "bank_identifier" key'i "bank_identifier_pattern"
-- olarak yeniden adlandırılıyor. Böylece template'i devre dışı bırakmak
-- tek bir update ile mümkün: SET detection_rules = '{}'.
-- ============================================================

BEGIN;

UPDATE import_templates
SET detection_rules =
  (detection_rules - 'bank_identifier')
  || jsonb_build_object('bank_identifier_pattern', detection_rules->>'bank_identifier')
WHERE detection_rules ? 'bank_identifier'
  AND NOT (detection_rules ? 'bank_identifier_pattern');

INSERT INTO migrations_log (file_name, notes)
VALUES ('064_detection_rules_rename.sql',
  'Rename detection_rules.bank_identifier → bank_identifier_pattern (system templates Halyk + BCC)')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
