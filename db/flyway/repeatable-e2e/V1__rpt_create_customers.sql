CREATE TABLE rpt_customers (
    id      INT PRIMARY KEY,
    name    VARCHAR(100) NOT NULL,
    email   VARCHAR(150),
    active  BOOLEAN NOT NULL DEFAULT TRUE
);
