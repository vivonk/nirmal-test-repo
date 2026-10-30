CREATE TABLE rpt_orders (
    id          INT PRIMARY KEY,
    customer_id INT NOT NULL,
    amount      DECIMAL(12, 2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_rpt_orders_customer FOREIGN KEY (customer_id) REFERENCES rpt_customers (id)
);
