-- =====================================================================
-- Day 18 - Databases, Schemas and Table Types
-- Databricks + Snowflake - 70-Hour Programme - DataTrends.tech
-- Sunday 30 August 2026 - Block B
--
-- One statement at a time. Ctrl+Enter.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 - The container hierarchy
-- ---------------------------------------------------------------------
--   ACCOUNT  ->  DATABASE  ->  SCHEMA  ->  TABLE / VIEW / STAGE / ...
--
-- Last Sunday, fifty of you shared ONE Databricks workspace, so every
-- table had to be namespaced with MY_ID or you would overwrite each other.
-- Here, each of you owns an entire ACCOUNT. Nobody can touch your objects.
-- That is the difference between a shared workspace and your own tenant.

USE ROLE ACCOUNTADMIN;

-- If you missed the last worksheet, or something failed, these two lines
-- build what you need. If you already have them, they do nothing at all.
CREATE WAREHOUSE IF NOT EXISTS MY_WH
    WAREHOUSE_SIZE = 'XSMALL'  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE;
USE WAREHOUSE MY_WH;

CREATE DATABASE IF NOT EXISTS MY_DB;
USE DATABASE MY_DB;

-- Two schemas: one for data as it arrives, one for data we have cleaned.
-- This is the same Bronze / Silver idea from Databricks, with SQL names.
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;

SHOW SCHEMAS IN DATABASE MY_DB;

-- Note the two you did not create: PUBLIC (given to every database) and
-- INFORMATION_SCHEMA (a read-only catalogue, one per database).

USE SCHEMA RAW;
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA();


-- ---------------------------------------------------------------------
-- 2 - Three kinds of table, and what you give up for each
-- ---------------------------------------------------------------------
-- PERMANENT  - Time Travel (1 day on trial, up to 90 on Enterprise)
--              PLUS 7 days of Fail-safe you cannot switch off or reach.
--              You pay storage for all of it.
-- TRANSIENT  - Time Travel 0 or 1 day, NO Fail-safe. Cheaper.
-- TEMPORARY  - lives inside THIS session only. Closes with the tab.

CREATE OR REPLACE TABLE           T_PERMANENT (id INT, note VARCHAR);
CREATE OR REPLACE TRANSIENT TABLE T_TRANSIENT (id INT, note VARCHAR);
CREATE OR REPLACE TEMPORARY TABLE T_TEMPORARY (id INT, note VARCHAR);

SHOW TABLES IN SCHEMA MY_DB.RAW;

SELECT "name", "kind", "rows", "retention_time"
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Look at "kind". Then look at "retention_time" - that number is the
-- Time Travel window in days, and it is what you are paying for.


-- ---------------------------------------------------------------------
-- 3 - Prove that TEMPORARY means what it says
-- ---------------------------------------------------------------------
INSERT INTO T_TEMPORARY VALUES (1, 'I will not survive this worksheet');
SELECT * FROM T_TEMPORARY;

-- Do not run this now - it is what you would do to check:
--   open a NEW worksheet, run SELECT * FROM MY_DB.RAW.T_TEMPORARY;
--   you get: Object 'T_TEMPORARY' does not exist.
-- The table is real, but only this session can see it.


-- ---------------------------------------------------------------------
-- 4 - Build a real table from a query (CTAS)
-- ---------------------------------------------------------------------
-- You do not have to declare columns. The query decides them.

CREATE OR REPLACE TABLE CUSTOMERS AS
SELECT C_CUSTKEY      AS customer_id,
       C_NAME         AS customer_name,
       C_MKTSEGMENT   AS segment,
       C_NATIONKEY    AS nation_id,
       C_ACCTBAL      AS balance
FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER;

SELECT COUNT(*) AS customer_rows FROM CUSTOMERS;

-- Where did the column types come from?
DESC TABLE CUSTOMERS;


-- ---------------------------------------------------------------------
-- 5 - The identifier trap that will bite somebody tonight
-- ---------------------------------------------------------------------
-- An unquoted name is folded to UPPERCASE and stored that way.
-- A "double quoted" name is stored EXACTLY as typed - and from then on
-- you must quote it every single time, forever.

CREATE OR REPLACE TABLE quiet_table   (id INT);   -- stored as QUIET_TABLE
CREATE OR REPLACE TABLE "loud_table"  (id INT);   -- stored as loud_table

SELECT * FROM QUIET_TABLE;      -- works
SELECT * FROM quiet_table;      -- works - same object
SELECT * FROM "loud_table";     -- works
-- SELECT * FROM loud_table;    -- FAILS. Uncomment to see the error.

-- Rule for the rest of your career: never use double quotes in a name
-- unless somebody is paying you to.

DROP TABLE "loud_table";
DROP TABLE QUIET_TABLE;


-- ---------------------------------------------------------------------
-- 6 - A view stores no rows
-- ---------------------------------------------------------------------
-- Exactly like createOrReplaceTempView in Spark: a name bound to a query.

CREATE OR REPLACE VIEW V_BIG_CUSTOMERS AS
SELECT customer_id, customer_name, segment, balance
FROM   CUSTOMERS
WHERE  balance > 9000;

SELECT COUNT(*) AS big_customers FROM V_BIG_CUSTOMERS;

-- How much storage did that view consume?
SHOW VIEWS LIKE 'V_BIG_CUSTOMERS';
-- None. There are no bytes. There is only a definition.


-- ---------------------------------------------------------------------
-- 7 - The catalogue, as a table you can query
-- ---------------------------------------------------------------------
-- SHOW commands are convenient. INFORMATION_SCHEMA is queryable SQL,
-- so you can filter, join and aggregate it.

SELECT TABLE_SCHEMA,
       TABLE_NAME,
       TABLE_TYPE,
       ROW_COUNT,
       BYTES
FROM   MY_DB.INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA IN ('RAW', 'CURATED')
ORDER  BY TABLE_SCHEMA, TABLE_NAME;

SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM   MY_DB.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_NAME = 'CUSTOMERS'
ORDER  BY ORDINAL_POSITION;


-- ---------------------------------------------------------------------
-- 8 - Drop it. Then get it back.
-- ---------------------------------------------------------------------
-- A teaser for Day 24. Notice you did not restore from a backup, and
-- nobody had to be phoned.

CREATE OR REPLACE TABLE OOPS AS SELECT 1 AS id, 'important' AS note;
SELECT * FROM OOPS;

DROP TABLE OOPS;
-- SELECT * FROM OOPS;          -- does not exist

UNDROP TABLE OOPS;
SELECT * FROM OOPS;             -- back, with its data

DROP TABLE OOPS;

-- This works because of Time Travel, and Time Travel is why a PERMANENT
-- table costs more to store than a TRANSIENT one. You are paying for the
-- ability to undo. Now section 2 makes sense.


-- ---------------------------------------------------------------------
-- 9 - YOUR TURN  (6 minutes)
-- ---------------------------------------------------------------------
-- 1. In MY_DB.CURATED, create a TRANSIENT table called SUPPLIERS from
--    SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER, keeping only
--    S_SUPPKEY, S_NAME and S_NATIONKEY.
-- 2. Confirm with SHOW TABLES that its "kind" is TRANSIENT and its
--    retention_time is what you expected.
-- 3. Paste your row count in the chat.
-- 4. One line: name one situation where you would deliberately choose a
--    TRANSIENT table over a PERMANENT one.

-- YOUR CODE HERE



-- ---------------------------------------------------------------------
-- 10 - Tidy up
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS T_PERMANENT;
DROP TABLE IF EXISTS T_TRANSIENT;
-- T_TEMPORARY needs no cleanup. It leaves when you do.

ALTER WAREHOUSE MY_WH SUSPEND;

-- IF YOU SEE:  Invalid state. Warehouse 'MY_WH' cannot be suspended.
-- That is NOT an error you need to fix. It means the warehouse was
-- ALREADY asleep - AUTO_SUSPEND got there before you did. Good news.

