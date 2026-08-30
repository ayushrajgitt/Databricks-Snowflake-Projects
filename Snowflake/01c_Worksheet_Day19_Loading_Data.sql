-- =====================================================================
-- Day 19 - Loading Data into Snowflake
-- Databricks + Snowflake - 70-Hour Programme - DataTrends.tech
-- Sunday 30 August 2026 - Block C
--
-- NOTHING IS DOWNLOADED AND NOTHING IS UPLOADED IN THIS WORKSHEET.
-- We write a file out of Snowflake, then load it back in, so all fifty
-- of us produce the same file with nothing to install and nothing to
-- go wrong. Section 11 shows the upload path separately.
--
-- One statement at a time. Ctrl+Enter.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0 - Make sure you are standing somewhere
-- ---------------------------------------------------------------------
-- Run all of these even if you think you already have them. Every one is
-- guarded, so if the object exists nothing happens. If you joined late or
-- something failed earlier, this is what puts you back on the same page
-- as everyone else.

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS MY_WH
    WAREHOUSE_SIZE = 'XSMALL'  AUTO_SUSPEND = 60  AUTO_RESUME = TRUE;
USE WAREHOUSE MY_WH;

CREATE DATABASE IF NOT EXISTS MY_DB;
USE DATABASE MY_DB;

CREATE SCHEMA IF NOT EXISTS RAW;
USE SCHEMA RAW;

-- All four must have a value. If any is NULL, stop and tell me in chat.
SELECT CURRENT_ROLE()      AS my_role,
       CURRENT_WAREHOUSE() AS my_warehouse,
       CURRENT_DATABASE()  AS my_database,
       CURRENT_SCHEMA()    AS my_schema;


-- ---------------------------------------------------------------------
-- 1 - A file format is a reusable description of "what the file looks like"
-- ---------------------------------------------------------------------
-- Write it once. Then never argue about delimiters again.

CREATE OR REPLACE FILE FORMAT CSV_STD
    TYPE                         = CSV
    FIELD_DELIMITER              = ','
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL', 'null')
    EMPTY_FIELD_AS_NULL          = TRUE;

SHOW FILE FORMATS;


-- ---------------------------------------------------------------------
-- 2 - A stage is a landing zone
-- ---------------------------------------------------------------------
-- Same job as the Unity Catalog Volume you used for Auto Loader last
-- Sunday: a place files sit BEFORE they are a table.
--
-- INTERNAL stage = storage Snowflake manages for you.
-- EXTERNAL stage = a pointer to your own S3 / Azure / GCS bucket.

CREATE OR REPLACE STAGE MY_STAGE
    FILE_FORMAT = CSV_STD
    COMMENT     = 'Landing zone - Day 19';

LIST @MY_STAGE;        -- empty. Nothing has landed yet.


-- ---------------------------------------------------------------------
-- 3 - Make a file, without leaving Snowflake
-- ---------------------------------------------------------------------
-- COPY INTO has two directions. Pointed at a STAGE it writes files out.
-- Pointed at a TABLE it reads files in. Same command, opposite way.

COPY INTO @MY_STAGE/orders/orders_1.csv
FROM (
    SELECT O_ORDERKEY,
           O_CUSTKEY,
           O_ORDERSTATUS,
           O_TOTALPRICE,
           O_ORDERDATE
    FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
    LIMIT  5000
)
FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_OPTIONALLY_ENCLOSED_BY = '"')
HEADER      = TRUE
SINGLE      = TRUE
OVERWRITE   = TRUE;

LIST @MY_STAGE/orders/;

-- There is now one real CSV file sitting in your account. Look at its
-- size. Nobody uploaded it.


-- ---------------------------------------------------------------------
-- 4 - Read the file BEFORE you commit to loading it
-- ---------------------------------------------------------------------
-- This is the habit that separates people who load data cleanly from
-- people who load data twice. $1, $2, $3 are column positions.

SELECT $1 AS orderkey,
       $2 AS custkey,
       $3 AS status,
       $4 AS totalprice,
       $5 AS orderdate
FROM   @MY_STAGE/orders/orders_1.csv (FILE_FORMAT => CSV_STD)
LIMIT  5;

-- You just ran SQL against a file that is not a table.


-- ---------------------------------------------------------------------
-- 5 - The table it is going to land in
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ORDERS_RAW (
    o_orderkey    NUMBER,
    o_custkey     NUMBER,
    o_orderstatus VARCHAR(1),
    o_totalprice  NUMBER(12,2),
    o_orderdate   DATE
);


-- ---------------------------------------------------------------------
-- 6 - Load it
-- ---------------------------------------------------------------------
COPY INTO ORDERS_RAW
FROM  @MY_STAGE/orders/
FILE_FORMAT = (FORMAT_NAME = CSV_STD)
ON_ERROR    = 'ABORT_STATEMENT';

-- Read the result grid, not just the green tick:
--   file          - which file
--   status        - LOADED
--   rows_parsed   - how many rows were in the file
--   rows_loaded   - how many made it into the table
-- When those last two disagree, you have a problem worth finding.

SELECT COUNT(*) AS rows_in_table FROM ORDERS_RAW;


-- ---------------------------------------------------------------------
-- 7 - *** RUN THE SAME COPY AGAIN. ***
-- ---------------------------------------------------------------------
-- Nothing about the statement has changed. Nothing about the file has
-- changed. Predict the answer before you press Ctrl+Enter.

COPY INTO ORDERS_RAW
FROM  @MY_STAGE/orders/
FILE_FORMAT = (FORMAT_NAME = CSV_STD)
ON_ERROR    = 'ABORT_STATEMENT';

SELECT COUNT(*) AS rows_in_table FROM ORDERS_RAW;

-- Snowflake remembers which FILES it has already loaded into this table,
-- and it skips them. Not which rows. Which files.
--
-- That is the same guarantee Auto Loader gave you last Sunday with its
-- checkpoint folder. Two different companies, two different products,
-- the same answer to the same problem: track the file, not the row.
--
-- The memory here is called load metadata, it lives on the table, and
-- it expires after 64 days.


-- ---------------------------------------------------------------------
-- 8 - How to load the same file on purpose, and why you usually should not
-- ---------------------------------------------------------------------
COPY INTO ORDERS_RAW
FROM  @MY_STAGE/orders/
FILE_FORMAT = (FORMAT_NAME = CSV_STD)
FORCE       = TRUE;

SELECT COUNT(*) AS rows_in_table FROM ORDERS_RAW;   -- now doubled

-- FORCE = TRUE ignores the load metadata. It does not check for
-- duplicates, because COPY INTO has never checked for duplicates.
-- Duplicate rows are your problem, not Snowflake's.

TRUNCATE TABLE ORDERS_RAW;

COPY INTO ORDERS_RAW
FROM  @MY_STAGE/orders/
FILE_FORMAT = (FORMAT_NAME = CSV_STD)
FORCE       = TRUE;

SELECT COUNT(*) AS rows_in_table FROM ORDERS_RAW;   -- back to 5000


-- ---------------------------------------------------------------------
-- 9 - The receipt: what has ever been loaded into this table?
-- ---------------------------------------------------------------------
SELECT FILE_NAME,
       ROW_COUNT,
       ROW_PARSED,
       FILE_SIZE,
       STATUS,
       LAST_LOAD_TIME
FROM   TABLE(MY_DB.INFORMATION_SCHEMA.COPY_HISTORY(
           TABLE_NAME => 'MY_DB.RAW.ORDERS_RAW',
           START_TIME => DATEADD(hour, -2, CURRENT_TIMESTAMP())))
ORDER  BY LAST_LOAD_TIME DESC;


-- ---------------------------------------------------------------------
-- 10 - Now break it deliberately
-- ---------------------------------------------------------------------
-- Real files are dirty. Write one where roughly one row in seven has a
-- word where a price should be.

COPY INTO @MY_STAGE/bad/orders_bad.csv
FROM (
    SELECT TO_VARCHAR(O_ORDERKEY)  AS c1,
           TO_VARCHAR(O_CUSTKEY)   AS c2,
           O_ORDERSTATUS           AS c3,
           CASE WHEN MOD(O_ORDERKEY, 7) = 0
                THEN 'not_a_price'
                ELSE TO_VARCHAR(O_TOTALPRICE)
           END                     AS c4,
           TO_VARCHAR(O_ORDERDATE) AS c5
    FROM   SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
    LIMIT  700
)
FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_OPTIONALLY_ENCLOSED_BY = '"')
HEADER      = TRUE
SINGLE      = TRUE
OVERWRITE   = TRUE;

-- 10a - LOOK before loading. VALIDATION_MODE loads nothing at all;
--       it just reports what would have gone wrong.
COPY INTO ORDERS_RAW
FROM  @MY_STAGE/bad/
FILE_FORMAT     = (FORMAT_NAME = CSV_STD)
VALIDATION_MODE = 'RETURN_ERRORS';

-- 10b - ON_ERROR decides what happens when a row will not parse.
--       ABORT_STATEMENT (the default) - load nothing, fail loudly
--       CONTINUE                      - skip the bad ROWS, keep the good
--       SKIP_FILE                     - abandon the whole FILE
--       SKIP_FILE_5%                  - abandon it only if >5% is bad

COPY INTO ORDERS_RAW
FROM  @MY_STAGE/bad/
FILE_FORMAT = (FORMAT_NAME = CSV_STD)
ON_ERROR    = 'CONTINUE';

-- Compare rows_parsed with rows_loaded in that result. The gap is the
-- rows you silently threw away. CONTINUE is convenient and it is also
-- how bad data quietly disappears. Decide on purpose, every time.

SELECT COUNT(*) AS rows_in_table FROM ORDERS_RAW;


-- ---------------------------------------------------------------------
-- 11 - The other way in: upload a file yourself
-- ---------------------------------------------------------------------
-- Follow along on screen; do not type this.
--
-- From a terminal with SnowSQL installed, the command is:
--     PUT file://C:/data/orders.csv @MY_STAGE/manual/ AUTO_COMPRESS=TRUE;
--
-- PUT cannot run from a Snowsight worksheet - it needs a client that can
-- reach your filesystem. Snowsight gives you the same thing with a button:
--
--     Data  >  Databases  >  MY_DB  >  RAW  >  Stages  >  MY_STAGE
--            >  + Files  >  choose your file  >  Upload
--
-- Then LIST @MY_STAGE/manual/ and COPY INTO exactly as above. The load
-- side does not care how the file arrived.


-- ---------------------------------------------------------------------
-- 12 - External stages and Snowpipe - concept tonight, hands-on later
-- ---------------------------------------------------------------------
-- An EXTERNAL stage points at a bucket you own. The files never move
-- into Snowflake; Snowflake reads them where they are.
--
--   CREATE STAGE S3_LANDING
--       URL         = 's3://my-company-bucket/incoming/'
--       CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...')
--       FILE_FORMAT = CSV_STD;
--
-- SNOWPIPE runs a COPY INTO for you whenever a new file appears:
--
--   CREATE PIPE ORDERS_PIPE
--       AUTO_INGEST = TRUE
--   AS COPY INTO ORDERS_RAW FROM @S3_LANDING FILE_FORMAT = (FORMAT_NAME = CSV_STD);
--
-- Both are commented out because they need cloud credentials we are not
-- putting in a classroom worksheet.
--
-- Snowpipe is per-file, event-driven, serverless, billed per file. If
-- that sounds familiar, it should: it is the same shape as Auto Loader
-- in file-notification mode. COPY INTO is the batch version of the same
-- idea, and it is what you will use for the capstone.


-- ---------------------------------------------------------------------
-- 13 - YOUR TURN  (10 minutes)
-- ---------------------------------------------------------------------
-- 1. Unload 2000 rows of SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
--    (columns L_ORDERKEY, L_PARTKEY, L_QUANTITY, L_EXTENDEDPRICE,
--     L_SHIPDATE) to @MY_STAGE/lineitem/lineitem_1.csv
-- 2. Query the file with $1..$5 before loading it. Paste your first
--    L_SHIPDATE value in the chat.
-- 3. Create LINEITEM_RAW with sensible types and COPY INTO it.
-- 4. Run the same COPY INTO a second time. Paste what the result says.
-- 5. Show your COPY_HISTORY for LINEITEM_RAW.

-- YOUR CODE HERE



-- ---------------------------------------------------------------------
-- 14 - Tidy up before you close the laptop
-- ---------------------------------------------------------------------
REMOVE @MY_STAGE/bad/;
LIST   @MY_STAGE;

ALTER WAREHOUSE MY_WH SUSPEND;

-- IF YOU SEE:  Invalid state. Warehouse 'MY_WH' cannot be suspended.
-- That is NOT an error you need to fix. It means the warehouse was
-- ALREADY asleep - AUTO_SUSPEND got there before you did. Good news.


-- Keep ORDERS_RAW and MY_STAGE. You will want them on Day 20.
