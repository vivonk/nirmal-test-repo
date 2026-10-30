-- Repeatable migration: re-applied when this file's checksum changes. Must be idempotent.
-- v2 (DBOPS-3308 E2E): checksum changed -> Flyway must re-apply on next migrate.
CREATE OR REPLACE VIEW rpt_active_customers AS
SELECT id, name, email, active
FROM rpt_customers
WHERE active = TRUE;
