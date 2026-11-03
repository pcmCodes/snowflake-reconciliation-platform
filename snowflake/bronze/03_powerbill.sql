-- =============================================================================
-- Bronze layer: PowerBill (billing system) raw landings.
-- =============================================================================

CREATE OR REPLACE TABLE bronze.pb_customers (
    customer_code  STRING,
    customer_name  STRING,
    address_city   STRING,
    postal_code    STRING,
    country        STRING,
    email          STRING,
    phone          STRING,
    account_status STRING,
    _source_file   STRING,
    _loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.pb_customers
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/powerbill/pb_customers.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.pb_invoices (
    invoice_id     STRING,
    customer_code  STRING,
    invoice_date   STRING,
    due_date       STRING,
    total_amount   STRING,
    invoice_status STRING,
    billing_period STRING,
    _source_file   STRING,
    _loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.pb_invoices
FROM (SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/powerbill/pb_invoices.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.pb_invoice_lines (
    line_id     STRING,
    invoice_id  STRING,
    description STRING,
    quantity    STRING,
    unit_price  STRING,
    line_amount STRING,
    tax_amount  STRING,
    _source_file STRING,
    _loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.pb_invoice_lines
FROM (SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/powerbill/pb_invoice_lines.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;
