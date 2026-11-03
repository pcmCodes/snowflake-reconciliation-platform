# Data Model

## Source systems (synthetic)

### Salesforce (CRM)
- `sf_accounts(account_id PK, account_name, billing_city, billing_postal_code, billing_country, phone, website, industry, segment, account_status, created_date, last_modified_date)`
- `sf_opportunities(opportunity_id PK, account_id FK, opportunity_name, stage, amount, close_date, created_date)`
- `sf_contacts(contact_id PK, account_id FK, first_name, last_name, email, phone)`

### Dynamics AX (ERP)
- `ax_customers(customer_id PK, customer_name, city, postal_code, country, phone, email, tax_id, credit_limit, status)`
- `ax_work_orders(work_order_id PK, customer_id FK, item_id FK, description, quantity, amount, status, created_date, completed_date)`
- `ax_items(item_id PK, item_name, category, unit_price)`
- `ax_contracts(contract_id PK, customer_id FK, contract_name, start_date, end_date, annual_value, status)`

### PowerBill (Billing)
- `pb_customers(customer_code PK, customer_name, address_city, postal_code, country, email, phone, account_status)`
- `pb_invoices(invoice_id PK, customer_code FK, invoice_date, due_date, total_amount, invoice_status, billing_period)`
- `pb_invoice_lines(line_id PK, invoice_id FK, description, quantity, unit_price, line_amount, tax_amount)`

## Silver (conformed)

`source_system` + `source_*_id` are always retained so any Gold row traces back to its origin.

- `silver.customers(source_system, source_customer_id, customer_name, customer_name_normalized, tax_id, email, phone, phone_normalized, billing_city, billing_postal_code, billing_country, segment, customer_status, source_extracted_at, etl_loaded_at)`
- `silver.opportunities(opportunity_id, source_system, source_account_id, opportunity_name, stage, amount, close_date, created_date, etl_loaded_at)`
- `silver.work_orders(work_order_id, source_system, source_customer_id, item_id, description, quantity, amount, status, created_date, completed_date, etl_loaded_at)`
- `silver.contracts(contract_id, source_system, source_customer_id, contract_name, start_date, end_date, annual_value, status, etl_loaded_at)`
- `silver.invoices(invoice_id, source_system, source_customer_id, invoice_date, due_date, total_amount, invoice_status, billing_period, etl_loaded_at)`
- `silver.invoice_lines(line_id, invoice_id, description, quantity, unit_price, line_amount, tax_amount, etl_loaded_at)`
- `silver.assets(item_id, item_name, category, unit_price, etl_loaded_at)`

## Gold (dimensional)

### `dim_customer` (SCD Type 2)
| Column | Type | Notes |
|---|---|---|
| `customer_sk` | NUMBER | Surrogate key (autoincrement) |
| `customer_bk` | STRING | Golden business key e.g. `CUST-00007` |
| `customer_name` | STRING | Reconciled name |
| `tax_id` | STRING | |
| `segment` | STRING | |
| `customer_status` | STRING | |
| `billing_city` | STRING | |
| `billing_postal_code` | STRING | |
| `billing_country` | STRING | |
| `effective_from` | TIMESTAMP_NTZ | |
| `effective_to` | TIMESTAMP_NTZ | `NULL`/`9999-12-31` = current |
| `is_current` | BOOLEAN | |
| `record_hash` | STRING | MD5 of tracked attributes |
| `etl_loaded_at` | TIMESTAMP_NTZ | |

### `bridge_customer_sources`
`customer_bk, source_system, source_customer_id, match_method (DETERMINISTIC|FUZZY|MANUAL), match_score (0–100), etl_loaded_at`

### Other Gold objects
- `dim_contract` (SCD2): `contract_sk, contract_bk, customer_bk, contract_name, start_date, end_date, annual_value, status, effective_from, effective_to, is_current, record_hash`
- `dim_asset`: `asset_sk, asset_bk, item_name, category, unit_price`
- `dim_date`: `date_key, full_date, day, month, month_name, quarter, year, is_weekend`
- `fact_invoice`: `invoice_sk, invoice_bk, customer_bk, contract_bk, invoice_date, invoice_date_key, due_date, billing_period, total_amount, expected_amount, variance_amount, variance_flag, invoice_status, source_system, etl_loaded_at`
- `fact_work_order`: `work_order_sk, work_order_bk, customer_bk, asset_bk, work_order_date, completed_date, quantity, amount, status, source_system, etl_loaded_at`
- `revenue_leakage_exceptions`: `exception_id, exception_type, customer_bk, source_system, source_ref_id, expected_amount, actual_amount, variance_amount, exception_date, severity, exception_status, description, detected_at`

## Cardinality & grain
- `dim_customer` grain: one row per golden customer per version (SCD2).
- `fact_invoice` grain: one row per PowerBill invoice (conformed to golden customer).
- `revenue_leakage_exceptions` grain: one row per detected exception per run (idempotent by natural key: `exception_type || '-' || source_ref_id`).
