-- =============================================================================
-- Bronze layer: Salesforce (CRM) raw landings.
-- Grain: one row per source record. Source columns kept as raw strings; Silver
-- performs typing/cleansing. Lineage via _source_file (METADATA$FILENAME) and
-- _loaded_at. Tables are CREATE OR REPLACE + COPY (idempotent re-runs).
-- =============================================================================

CREATE OR REPLACE TABLE bronze.sf_accounts (
    account_id          STRING,
    account_name        STRING,
    billing_city        STRING,
    billing_postal_code STRING,
    billing_country     STRING,
    phone               STRING,
    website             STRING,
    industry            STRING,
    segment             STRING,
    account_status      STRING,
    created_date        STRING,
    last_modified_date  STRING,
    _source_file        STRING,
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.sf_accounts
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/salesforce/sf_accounts.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.sf_opportunities (
    opportunity_id   STRING,
    account_id       STRING,
    opportunity_name STRING,
    stage            STRING,
    amount           STRING,
    close_date       STRING,
    created_date     STRING,
    _source_file     STRING,
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.sf_opportunities
FROM (SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/salesforce/sf_opportunities.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;

CREATE OR REPLACE TABLE bronze.sf_contacts (
    contact_id   STRING,
    account_id   STRING,
    first_name   STRING,
    last_name    STRING,
    email        STRING,
    phone        STRING,
    _source_file STRING,
    _loaded_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
COPY INTO bronze.sf_contacts
FROM (SELECT $1,$2,$3,$4,$5,$6, METADATA$FILENAME, CURRENT_TIMESTAMP()
      FROM @recon_csv_stage/salesforce/sf_contacts.csv)
FILE_FORMAT = (FORMAT_NAME = recon_platform.bronze.ff_recon_csv)
ON_ERROR    = ABORT_STATEMENT;
