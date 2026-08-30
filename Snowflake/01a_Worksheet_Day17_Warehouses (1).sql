-- =====================================================================
-- Day 17 - Snowflake Warehouses and Compute
-- Databricks + Snowflake - 70-Hour Programme - DataTrends.tech
-- Sunday 30 August 2026 - Block A
--
-- Paste this into a Snowsight worksheet.
-- Run ONE statement at a time: put the cursor inside it, press Ctrl+Enter.
-- (Ctrl+Shift+Enter runs the whole worksheet. Do not do that yet.)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0 - Health check. Run this first, every session, forever.
-- ---------------------------------------------------------------------
-- Four things decide whether any query works: who you are, what role you
-- are wearing, which warehouse is paying, and which database you are in.

SELECT CURRENT_USER()      AS my_user,
       CURRENT_ROLE()      AS my_role,
       CURRENT_WAREHOUSE() AS my_warehouse,
       CURRENT_DATABASE()  AS my_database,
       CURRENT_REGION()    AS my_region;

-- And the one that cannot be changed later:
SELECT CURRENT_VERSION() AS version;
SHOW PARAMETERS LIKE 'TIMEZONE' IN ACCOUNT;


-- ---------------------------------------------------------------------
-- 1 - Rebuild the warehouse from Day 16 (safe to re-run)
-- ---------------------------------------------------------------------
-- IF NOT EXISTS, not OR REPLACE. OR REPLACE would drop the warehouse and
-- kill anything running on it. In a shared team account that is a very
-- bad afternoon.

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS MY_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE MY_WH;

-- You also need a DATABASE selected, not just a warehouse.
-- Look at the top of this screen. If it says "Choose database", you have
-- no current database - and several things later in this worksheet will
-- fail with "Invalid identifier". Fix it now:

CREATE DATABASE IF NOT EXISTS MY_DB;
USE DATABASE MY_DB;
USE SCHEMA   PUBLIC;

SELECT CURRENT_WAREHOUSE() AS wh, CURRENT_DATABASE() AS db, CURRENT_SCHEMA() AS sch;
-- All three must have a value. None of them may be NULL.


-- ---------------------------------------------------------------------
-- 2 - What is actually inside a warehouse?
-- ---------------------------------------------------------------------
-- Nothing. There are no tables in here. A warehouse is a rented cluster
-- of machines that switches on, runs your query, and switches off.

SHOW WAREHOUSES LIKE 'MY_WH';

-- Read the row you just got back, by column name:
SELECT "name",
       "state",
       "size",
       "auto_suspend",
       "auto_resume",
       "min_cluster_count",
       "max_cluster_count"
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- RESULT_SCAN(LAST_QUERY_ID()) turns the output of the previous statement
-- into a table you can query. Remember this one - SHOW commands are not
-- real queries, and this is how you filter them.


-- ---------------------------------------------------------------------
-- 3 - Size is a cost decision, not a speed decision
-- ---------------------------------------------------------------------
-- Each size up doubles the machines AND doubles the credits per hour.
--
--    XSMALL = 1 credit/hour     SMALL = 2     MEDIUM = 4
--    LARGE  = 8                 XLARGE = 16   ... and so on.
--
-- A bigger warehouse does not make a small query faster.
-- It makes a BIG query faster. Those are different sentences.

-- A small query. Note the time.
SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- Do NOT leave this at SMALL. We put it back two statements later.
ALTER WAREHOUSE MY_WH SET WAREHOUSE_SIZE = 'SMALL';

-- The same small query on twice the machines.
SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- Put it back. Every second at SMALL costs twice as much.
ALTER WAREHOUSE MY_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- Notice the resize needed no reload, no repartition, no restart.
-- The storage never found out it happened.


-- ---------------------------------------------------------------------
-- 4 - Scale UP versus scale OUT
-- ---------------------------------------------------------------------
-- Scale UP  = a bigger warehouse. Fixes ONE slow query.
-- Scale OUT = more clusters of the same size. Fixes FIFTY people queuing.
--
-- Multi-cluster needs Enterprise or above. Yours is Enterprise or
-- Business Critical, so this will work.

ALTER WAREHOUSE MY_WH SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    SCALING_POLICY    = 'STANDARD';

SHOW WAREHOUSES LIKE 'MY_WH';
SELECT "name", "size", "min_cluster_count", "max_cluster_count", "scaling_policy"
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- MIN 1 means it costs nothing extra while you are the only user.
-- Clusters 2 and 3 only start if queries begin to queue.


-- ---------------------------------------------------------------------
-- 5 - AUTO_SUSPEND is the single most important setting you own
-- ---------------------------------------------------------------------
-- 60 seconds. Not 600. A warehouse left running overnight by accident is
-- the number one way a trial account dies before the course ends.

ALTER WAREHOUSE MY_WH SET AUTO_SUSPEND = 60;

ALTER WAREHOUSE MY_WH SUSPEND;
SHOW WAREHOUSES LIKE 'MY_WH';       -- state: SUSPENDED

-- Now ask a question without switching anything back on.
SELECT COUNT(*) AS customers
FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER;

SHOW WAREHOUSES LIKE 'MY_WH';       -- state: STARTED - it woke up by itself


-- ---------------------------------------------------------------------
-- 6 - A guard rail on the whole account
-- ---------------------------------------------------------------------
-- A resource monitor watches credit spend and can suspend warehouses
-- when a limit is crossed. Set this once, tonight, and forget it.

USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS COURSE_GUARD
    WITH CREDIT_QUOTA = 20
         FREQUENCY       = MONTHLY
         START_TIMESTAMP = IMMEDIATELY
    TRIGGERS ON 75  PERCENT DO NOTIFY
             ON 90  PERCENT DO SUSPEND
             ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE MY_WH SET RESOURCE_MONITOR = COURSE_GUARD;

SHOW RESOURCE MONITORS;

-- SUSPEND lets running queries finish, then stops the warehouse.
-- SUSPEND_IMMEDIATE kills them mid-flight. That difference matters.


-- ---------------------------------------------------------------------
-- 7 - What did I spend?
-- ---------------------------------------------------------------------
-- Your own history is instant. The account-wide views (ACCOUNT_USAGE)
-- lag by up to three hours, so on a young account they look empty.
-- That is latency, not a bug.

-- NOTE THE FULL NAME:  MY_DB.INFORMATION_SCHEMA
-- Every database gets its own INFORMATION_SCHEMA. There is no single
-- account-wide one. If you write INFORMATION_SCHEMA on its own with no
-- database selected, you get:
--     SQL compilation error: Invalid identifier INFORMATION_SCHEMA...
-- That error almost always means "no current database", not "bad SQL".

SELECT QUERY_TEXT,
       WAREHOUSE_NAME,
       WAREHOUSE_SIZE,
       TOTAL_ELAPSED_TIME / 1000 AS seconds,
       BYTES_SCANNED,
       START_TIME
FROM   TABLE(MY_DB.INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER  BY START_TIME DESC
LIMIT  10;


-- ---------------------------------------------------------------------
-- 8 - The cache that makes your second run look impossibly fast
-- ---------------------------------------------------------------------
-- Full treatment is Day 22. Tonight, just see it happen.

SELECT COUNT(*), SUM(O_TOTALPRICE)
FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- Run the exact same statement again. Milliseconds. No warehouse work
-- at all - the answer came from the result cache, and it was free.

-- Switch the cache off and it goes back to being a real query:
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*), SUM(O_TOTALPRICE)
FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;


-- ---------------------------------------------------------------------
-- 9 - YOUR TURN  (5 minutes)
-- ---------------------------------------------------------------------
-- 1. Set AUTO_SUSPEND on MY_WH to 120, confirm it with SHOW WAREHOUSES,
--    then set it back to 60.
-- 2. Find, in your own QUERY_HISTORY, the query that scanned the most
--    bytes tonight. Paste its seconds value in the chat.
-- 3. One line, in your own words: why does making the warehouse bigger
--    not help a query that reads ten rows?

-- YOUR CODE HERE

-- 1. Set AUTO_SUSPEND to 120
ALTER WAREHOUSE MY_WH SET AUTO_SUSPEND = 120;

-- Confirm it
SHOW WAREHOUSES LIKE 'MY_WH';


-- Set AUTO_SUSPEND back to 60
ALTER WAREHOUSE MY_WH SET AUTO_SUSPEND = 60;


-- 2. Find the query that scanned the most bytes tonight
```sql
SELECT QUERY_TEXT,
       WAREHOUSE_NAME,
       WAREHOUSE_SIZE,
       TOTAL_ELAPSED_TIME / 1000 AS seconds,
       BYTES_SCANNED,
       START_TIME
FROM TABLE(MY_DB.INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER BY BYTES_SCANNED DESC
LIMIT 1;

-- A bigger warehouse does not help a query that reads ten rows because the query is already small and does not need more compute power.


-- ---------------------------------------------------------------------
-- 10 - Before you move to the next worksheet
-- ---------------------------------------------------------------------
ALTER WAREHOUSE MY_WH SUSPEND;

-- IF YOU SEE:  Invalid state. Warehouse 'MY_WH' cannot be suspended.
-- That is NOT an error you need to fix. It means the warehouse was
-- ALREADY asleep - AUTO_SUSPEND got there before you did. Good news.

