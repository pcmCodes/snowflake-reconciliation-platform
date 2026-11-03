-- =============================================================================
-- 04_resource_monitors.sql
-- Per-warehouse resource monitors (monthly credit caps, notify -> suspend ->
-- suspend-immediate). Warehouse-level monitors also allow NOTIFY_USERS; here we
-- rely on NOTIFY (account admins with notifications enabled) to avoid requiring
-- pre-verified emails in a trial account.
-- =============================================================================

CREATE OR REPLACE RESOURCE MONITOR rm_recon_load
  WITH CREDIT_QUOTA = 25 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 80 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;

CREATE OR REPLACE RESOURCE MONITOR rm_recon_transform
  WITH CREDIT_QUOTA = 40 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 80 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;

CREATE OR REPLACE RESOURCE MONITOR rm_recon_reporting
  WITH CREDIT_QUOTA = 15 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 80 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;

-- Attach each monitor to its warehouse --------------------------------------
ALTER WAREHOUSE RECON_LOAD_WH      SET RESOURCE_MONITOR = rm_recon_load;
ALTER WAREHOUSE RECON_TRANSFORM_WH SET RESOURCE_MONITOR = rm_recon_transform;
ALTER WAREHOUSE RECON_REPORTING_WH SET RESOURCE_MONITOR = rm_recon_reporting;
