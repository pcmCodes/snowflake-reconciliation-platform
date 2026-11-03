# Data Quality & Reconciliation

The platform treats data quality as a first-class, testable artefact. Checks live in `snowflake/tests/` and are executed at the end of every pipeline run and in CI.

## Validation layers

### 1. Source-to-target row-count validation
Each layer's row counts are reconciled against the layer that feeds it:
- Bronze vs generated CSV counts (exact match expected).
- Silver vs Bronze (Silver ≤ Bronze because of de-duplication; captured as expected ratio).
- Gold facts vs Silver sources; Gold exceptions vs detected source rows.

A row-count mismatch fails the run.

### 2. Completeness checks
- No NULL business keys (`customer_bk`, `invoice_bk`, `contract_bk`, `work_order_bk`).
- No orphan foreign keys: every `fact_invoice.customer_bk` exists in `dim_customer`; every `fact_work_order.asset_bk` exists in `dim_asset`.
- Every invoice's customer is resolvable to a golden customer (else it is flagged as `ORPHAN_BILLING` in the leakage engine).
- Referential integrity between `silver.invoice_lines.invoice_id` and `silver.invoices.invoice_id`.

### 3. Traceability (SOX/ITGC)
- Every `revenue_leakage_exceptions` row carries `source_system` + `source_ref_id` pointing back to the originating source record, so an auditor can walk from a leakage exception to its raw evidence.
- `bridge_customer_sources` records *how* a customer was matched (`match_method`, `match_score`), giving an audit trail of entity-resolution decisions.

### 4. Data-quality rules (run in pipeline)
| Rule | Layer | Action on failure |
|---|---|---|
| `amount >= 0` | Silver invoices/work_orders | Quarantine row + log |
| `email` matches RFC-ish pattern | Silver customers | Set to NULL (masked downstream) |
| `contract.end_date >= contract.start_date` | Silver contracts | Flag invalid contract |
| `invoice.total_amount` ≈ Σ `invoice_lines.line_amount` | Silver | Flag as `BILLING_MISMATCH` |
| Unique `customer_bk` in `bridge_customer_sources` per source | Gold | Fail run |

## Tolerance for billing reconciliation
`BILLING_MISMATCH` is raised when `ABS(total_amount - expected_amount) > 1.00` (currency units). Tolerance is parameterised at the top of `05_revenue_leakage.sql`.

## CI integration
`run_pipeline.py` exits non-zero if any check fails, which fails the GitHub Actions CI job. Production deployment is blocked on a green CI run.
