# Architecture

## Design principles

1. **Layered (medallion)** — each layer has a single responsibility and a clear contract. Bronze is raw and immutable; Silver is clean and conformed; Gold is analytics-ready and dimensional.
2. **Idempotent** — every object is `CREATE OR REPLACE` or `MERGE`-based, so the pipeline re-runs safely without manual cleanup.
3. **Traceable** — every Gold row can be traced back to its Bronze/source row via `source_system` + `source_*_id` and the `bridge_customer_sources` mapping. Lineage metadata (`_source_file`, `_loaded_at`) is preserved in Bronze.
4. **Governed** — RBAC, dynamic data masking and resource monitors are part of the platform, not bolted on.
5. **Testable** — reconciliation and completeness checks are SQL assets that run in CI.

## Layers

### Bronze (raw landing)
- One table per source object (e.g. `bronze.sf_accounts`, `bronze.ax_contracts`, `bronze.pb_invoices`).
- Loaded from staged CSV via `COPY INTO` using a shared CSV file format.
- Columns are typed but otherwise raw. Two metadata columns are appended: `_source_file` (from `METADATA$FILENAME`) and `_loaded_at`.
- Loading warehouse: `RECON_LOAD_WH` (X-SMALL, auto-suspend 60s) — load work is lightweight and spiky.

### Silver (cleaned & conformed)
- One table per business entity, with `source_system` + `source_*_id` retained (resolution is deferred to Gold).
- Cleansing: trim/upper, NULL handling, phone/email normalization, a `customer_name_normalized` key (uppercase, alphanumeric only) for matching.
- De-duplication: keep latest row per natural key using `ROW_NUMBER() ... ORDER BY _loaded_at DESC`.
- Transform warehouse: `RECON_TRANSFORM_WH` (SMALL) — heavier joins/SCD2 work.

### Gold (dimensional + exceptions)
- `dim_customer` (SCD2), `dim_contract` (SCD2), `dim_asset`, `dim_date`.
- `fact_invoice`, `fact_work_order`.
- `bridge_customer_sources` — the entity-resolution mapping (golden customer ↔ each source ID, with `match_method` and `match_score`).
- `revenue_leakage_exceptions` — the leakage-detection output.

### Semantic
- Views over Gold for the Revenue Assurance dashboard, e.g. `v_revenue_assurance_summary`, `v_leakage_by_category`, `v_customer_360`, `v_invoice_vs_expected`.

## Entity resolution strategy

Implemented in `snowflake/gold/01_entity_resolution.sql`:

1. **Normalize** — `customer_name_normalized` (upper, alnum-only, trimmed) is produced in Silver.
2. **Deterministic** — cluster customers sharing the same `tax_id` (when present), or the same (`customer_name_normalized`, `billing_postal_code`). A representative key is assigned via window functions.
3. **Fuzzy** — for remaining singletons, match against existing clusters using `JAROWINKLER_SIMILARITY(customer_name_normalized) >= 90` within the same country; adopt the best cluster if found, else create a new golden customer.
4. **Golden key** — assigned as `CUST-00001`, `CUST-00002`, … and recorded in `bridge_customer_sources` with the match method and score.

> Production note: full transitive-closure clustering (connected components over match edges) is best done with Snowpark or an iterative SP. This implementation uses a pragmatic two-pass deterministic-then-fuzzy approach, documented as such.

## Revenue leakage engine

`snowflake/gold/05_revenue_leakage.sql` emits one row per detected exception:

| Exception type | Trigger |
|---|---|
| `WON_NOT_BILLED` | Salesforce opportunity `Closed Won` with no matching contract/invoice |
| `CONTRACT_NO_INVOICE` | Active AX contract with no PowerBill invoice in the period |
| `WORK_ORDER_NOT_INVOICED` | Completed AX work order with no matching invoice line |
| `BILLING_MISMATCH` | `fact_invoice.total_amount` ≠ expected amount (contract / work order) beyond tolerance |
| `ORPHAN_BILLING` | PowerBill customer not resolved to any SF/AX golden customer |
| `OVERDUE_UNCOLLECTED` | Invoice overdue beyond threshold and unpaid |

Each exception carries `severity`, `exception_status` (OPEN/REVIEWED/RESOLVED), `expected_amount`, `actual_amount`, `variance_amount` and `source_ref_id` for traceability.

## Warehousing strategy

| Warehouse | Size | Auto-suspend | Purpose |
|---|---|---|---|
| `RECON_LOAD_WH` | X-SMALL | 60s | COPY / PUT loads (spiky, low concurrency) |
| `RECON_TRANSFORM_WH` | SMALL | 60s | Silver + Gold transforms, SCD2 MERGE |
| `RECON_REPORTING_WH` | X-SMALL | 30s | Semantic-layer queries / dashboard refresh |

All auto-suspend; resource monitors cap monthly credit spend per environment (dev/staging/prod).

## Environments

`dev` → `staging` → `prod`, each a separate Snowflake database (`RECON_PLATFORM_DEV`, `RECON_PLATFORM_STAGING`, `RECON_PLATFORM`). Deployment is environment-gated in GitHub Actions; prod requires approval. This mirrors SOX/ITGC separation of duties.
