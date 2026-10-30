-- Repeatable migration: re-applied when this file's checksum changes. Must be idempotent.
CREATE OR REPLACE FUNCTION rpt_order_total(p_customer_id INTEGER)
RETURNS NUMERIC AS $$
    SELECT COALESCE(SUM(amount), 0) FROM rpt_orders WHERE customer_id = p_customer_id;
$$ LANGUAGE SQL STABLE;
