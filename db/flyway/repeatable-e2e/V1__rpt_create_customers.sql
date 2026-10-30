CREATE TABLE rpt_customers (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(100) NOT NULL,
    email   VARCHAR(150),
    active  BOOLEAN NOT NULL DEFAULT TRUE
);
