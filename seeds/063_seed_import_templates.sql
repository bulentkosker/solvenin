-- 063_seed_import_templates.sql
-- Seed 3 system import templates (Halyk, BCC, Generic Cashbook)

BEGIN;

INSERT INTO import_templates (name, file_format, country_code, language_code, bank_name, bank_identifier, target_module, is_system, is_public, locale, parser_config, detection_rules, metadata_config)
VALUES (
  'Halyk Bank KZ — Выписка по счету (PDF)',
  'pdf', 'KZ', 'ru', 'Halyk Bank', 'HSBKKZKX', 'bank_statement',
  true, true,
  '{"decimal_separator":".","thousand_separator":",","date_format":"DD.MM.YYYY"}'::jsonb,
  '{"row_detection":{"method":"y_coordinate_grouping","pattern":"^\\\\d{2}\\\\.\\\\d{2}\\\\.\\\\d{4}","y_tolerance":3},"fields":{"transaction_date":{"method":"x_coordinate_range","x_min":30,"x_max":75},"document_number":{"method":"x_coordinate_range","x_min":76,"x_max":175},"debit":{"method":"x_coordinate_range","x_min":165,"x_max":248},"credit":{"method":"x_coordinate_range","x_min":248,"x_max":340},"counterparty_name":{"method":"x_coordinate_range","x_min":340,"x_max":440,"use_all_rows":true},"payment_details":{"method":"x_coordinate_range","x_min":430,"x_max":545,"use_all_rows":true},"counterparty_bin":{"method":"regex_in_field","pattern":"БИН\\\\s*(\\\\d{12})","group":1},"external_reference":{"method":"regex_in_field","pattern":"Внешний референс[:\\\\s]+([\\\\w\\\\d]+)","group":1}}}'::jsonb,
  '{"bank_identifier":"HSBKKZKX","header_contains":"Народный Банк Казахстана"}'::jsonb,
  '{"account_iban":{"method":"regex","pattern":"(KZ\\\\d{18,20})"},"opening_balance":{"method":"regex","pattern":"Входящий остаток[:\\\\s]+([\\\\d\\\\s,.]+)"},"closing_balance":{"method":"regex","pattern":"Исходящий остаток[:\\\\s]+([\\\\d\\\\s,.]+)"},"period_start":{"method":"regex","pattern":"За период[:\\\\s]+(\\\\d{2}-\\\\d{2}-\\\\d{4})","date_format":"DD-MM-YYYY"},"period_end":{"method":"regex","pattern":"За период[:\\\\s]+\\\\d{2}-\\\\d{2}-\\\\d{4}\\\\s+(\\\\d{2}-\\\\d{2}-\\\\d{4})","date_format":"DD-MM-YYYY"},"client_bin":{"method":"regex","pattern":"ИИН/БИН\\\\s+(\\\\d{12})"},"bank_bik":{"method":"regex","pattern":"БИК\\\\s+(\\\\w+)"}}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO import_templates (name, file_format, country_code, language_code, bank_name, bank_identifier, target_module, is_system, is_public, locale, parser_config, detection_rules, metadata_config)
VALUES (
  'BCC Bank KZ — Обороты по счетам (PDF)',
  'pdf', 'KZ', 'ru', 'Bank CenterCredit', 'KCJBKZKX', 'bank_statement',
  true, true,
  '{"decimal_separator":",","thousand_separator":" ","date_format":"DD.MM.YYYY"}'::jsonb,
  '{"row_detection":{"method":"y_coordinate_grouping","pattern":"^\\\\d{2}\\\\.\\\\d{2}\\\\.\\\\d{4}$","y_tolerance":6,"skip_header_y":290,"date_x_min":60,"date_x_max":115,"stop_pattern":"Итого|Обороты|Исходящ"},"fields":{"transaction_date":{"method":"x_coordinate_range","x_min":60,"x_max":115},"document_number":{"method":"x_coordinate_range","x_min":28,"x_max":58},"debit":{"method":"x_coordinate_range","x_min":425,"x_max":495,"use_all_rows":true},"credit":{"method":"x_coordinate_range","x_min":495,"x_max":560,"use_all_rows":true},"knp_code":{"method":"x_coordinate_range","x_min":568,"x_max":598,"use_all_rows":true},"counterparty_name":{"method":"x_coordinate_range","x_min":290,"x_max":420,"use_all_rows":true},"payment_details":{"method":"x_coordinate_range","x_min":690,"x_max":850,"use_all_rows":true},"counterparty_bin":{"method":"regex_in_field","pattern":"\\\\b(\\\\d{12})\\\\b","group":1},"external_reference":{"method":"regex_in_field","pattern":"Внешний референс[:\\\\s]+([\\\\w\\\\d]+)","group":1}}}'::jsonb,
  '{"bank_identifier":"KCJBKZKX","header_contains":"ЦентрКредит"}'::jsonb,
  '{"account_iban":{"method":"regex","pattern":"ЖСК / ИИК[:\\\\s]+(KZ\\\\d{18,20})"},"opening_balance":{"method":"regex","pattern":"Входящее\\\\s+сальдо\\\\s*:\\\\s*([\\\\d\\\\s,.]+)"},"closing_balance":{"method":"regex","pattern":"Исходящее\\\\s+сальдо[:\\\\s]+([\\\\d\\\\s,.]+)"},"client_bin":{"method":"regex","pattern":"ИИН / БИН[:\\\\s]+(\\\\d{12})"},"bank_bik":{"method":"regex","pattern":"БСК / БИК[:\\\\s]+(\\\\w+)"}}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO import_templates (name, file_format, country_code, language_code, bank_name, bank_identifier, target_module, is_system, is_public, locale, parser_config, detection_rules, metadata_config)
VALUES (
  'Kasa/Banka Defteri — Günlük (XLSX)',
  'xlsx', 'KZ', 'tr', null, null, 'cash_register',
  true, true,
  '{"decimal_separator":".","thousand_separator":"","date_format":"DD.MM.YYYY"}'::jsonb,
  '{"sheet_pattern":".*","sheet_date_format":"DD.MM.YYYY","sections":[{"name":"cash","sheet_pattern":".*","start_row":7,"end_detection":"first_empty_in_col_B","columns":{"number":"B","description":"C","debit":"D","credit":"E"}},{"name":"bank","sheet_pattern":".*","start_row":7,"end_detection":"first_empty_in_col_B","columns":{"number":"I","description":"J","debit":"K","credit":"L"}}]}'::jsonb,
  '{"header_contains":"GÜNLÜK NAKİT KASA"}'::jsonb,
  '{"cash_opening_balance":{"method":"cell","sheet":0,"cell":"D5"},"bank_opening_balance":{"method":"cell","sheet":0,"cell":"K5"}}'::jsonb
) ON CONFLICT DO NOTHING;

INSERT INTO migrations_log (file_name, notes)
VALUES ('063_seed_import_templates.sql', 'Seed 3 system import templates: Halyk, BCC, Generic Cashbook')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
