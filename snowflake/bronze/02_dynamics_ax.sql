-- =============================================================================
-- Bronze layer: Microsoft Dynamics AX (ERP) raw landings.
-- =============================================================================

CREATE OR REPLACE TABLE bronze.ax_customers (
    customer_id   STRING,
    customer_name STRING,
    city          STRING,
    postal_code   STRING,
    country       STRING,
    phone         STRING,
    email         STRING,
    tax_id        STRING,
    credit_limit  STRING,
    status        STRING,
    _source_file  STRING,
    _loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.ax_customers
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/dynamics_ax/ax_customers.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.ax_work_orders (
    work_order_id  STRING,
    customer_id    STRING,
    item_id        STRING,
    description    STRING,
    quantity       STRING,
    amount         STRING,
    status         STRING,
    created_date   STRING,
    completed_date STRING,
    _source_file   STRING,
    _loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.ax_work_orders
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/dynamics_ax/ax_work_orders.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.ax_items (
    item_id      STRING,
    item_name    STRING,
    category     STRING,
    unit_price   STRING,
    _source_file STRING,
    _loaded_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.ax_items
FROM (SELECT $1,$2,$3,$4, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/dynamics_ax/ax_items.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.ax_contracts (
    contract_id   STRING,
    customer_id   STRING,
    contract_name STRING,
    start_date    STRING,
    end_date      STRING,
    annual_value  STRING,
    status        STRING,
    _source_file  STRING,
    _loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.ax_contracts
FROM (SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/dynamics_ax/ax_contracts.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;
