-- Repeatable migration (new in phase 2): idempotent.
CREATE OR REPLACE VIEW rpt_customer_count AS
SELECT COUNT(*) AS total_customers FROM rpt_customers;
