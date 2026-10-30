-- Repeatable migration: re-applied when this file's checksum changes. Must be idempotent.
CREATE OR REPLACE VIEW rpt_active_customers AS
SELECT id, name, email
FROM rpt_customers
WHERE active = TRUE;
