-- =============================================================================
-- Dynamic data masking (POPIA/GDPR-aligned): PII columns reveal clear values
-- only to privileged roles (RECON_ADMIN, RECON_ENGINEER); analysts/readers see
-- masked values. Policies live in a dedicated SECURITY schema (governance
-- separation). Must run AFTER silver + gold tables exist.
-- =============================================================================
USE ROLE ACCOUNTADMIN;            -- masking policies require a role with the privilege
USE DATABASE RECON_PLATFORM;

CREATE SCHEMA IF NOT EXISTS SECURITY;
USE SCHEMA SECURITY;

-- email: first char + masked local + real domain ----------------------------
CREATE OR REPLACE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RECON_ADMIN','RECON_ENGINEER','ACCOUNTADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE LEFT(val, 1) || '***@' || SPLIT_PART(val, '@', 2)
    END;

-- phone: keep last 4 digits -------------------------------------------------
CREATE OR REPLACE MASKING POLICY phone_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RECON_ADMIN','RECON_ENGINEER','ACCOUNTADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***-***-' || RIGHT(val, 4)
    END;

-- tax_id: keep last 3 characters -------------------------------------------
CREATE OR REPLACE MASKING POLICY tax_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RECON_ADMIN','RECON_ENGINEER','ACCOUNTADMIN') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '*****' || RIGHT(val, 3)
    END;

-- Apply policies to PII columns --------------------------------------------
ALTER TABLE RECON_PLATFORM.SILVER.CUSTOMERS MODIFY COLUMN email SET MASKING POLICY SECURITY.email_mask;
ALTER TABLE RECON_PLATFORM.SILVER.CUSTOMERS MODIFY COLUMN phone SET MASKING POLICY SECURITY.phone_mask;
ALTER TABLE RECON_PLATFORM.SILVER.CUSTOMERS MODIFY COLUMN tax_id SET MASKING POLICY SECURITY.tax_mask;
ALTER TABLE RECON_PLATFORM.GOLD.DIM_CUSTOMER MODIFY COLUMN tax_id SET MASKING POLICY SECURITY.tax_mask;
