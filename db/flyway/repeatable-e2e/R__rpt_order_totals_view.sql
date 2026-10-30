-- Repeatable migration: re-applied when this file's checksum changes. Must be idempotent.
CREATE OR REPLACE VIEW rpt_order_totals AS
SELECT customer_id, COALESCE(SUM(amount), 0) AS total_amount
FROM rpt_orders
GROUP BY customer_id;
