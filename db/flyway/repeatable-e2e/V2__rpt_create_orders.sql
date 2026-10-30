CREATE TABLE rpt_orders (
    id          SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES rpt_customers (id),
    amount      NUMERIC(12, 2) NOT NULL DEFAULT 0
);
