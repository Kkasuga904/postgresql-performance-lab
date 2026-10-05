\set ON_ERROR_STOP on

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS accounts;

CREATE TABLE accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_name text NOT NULL,
    balance numeric(12,2) NOT NULL CHECK (balance >= 0),
    status text NOT NULL CHECK (status IN ('active', 'suspended')),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE orders (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id bigint NOT NULL,
    status text NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')),
    total_amount numeric(10,2) NOT NULL,
    ordered_at timestamptz NOT NULL,
    note text NOT NULL
);

COMMENT ON TABLE orders IS 'Index/VACUUM labs: indexes are intentionally absent after setup.';

