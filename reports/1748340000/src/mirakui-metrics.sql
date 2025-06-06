CREATE OR REPLACE view pf AS
SELECT
  SCHEMA_NAME,
  -- DIGEST,
  DIGEST_TEXT,
  COUNT_STAR,
  round(SUM_TIMER_WAIT / pow(1000,4), 3) as SUM_TIMER_WAIT_SEC,
  round(MIN_TIMER_WAIT / pow(1000,4), 3) as MIN_TIMER_WAIT_SEC,
  round(AVG_TIMER_WAIT / pow(1000,4), 3) as AVG_TIMER_WAIT_SEC,
  round(MAX_TIMER_WAIT / pow(1000,4), 3) as MAX_TIMER_WAIT_SEC,
  round(SUM_LOCK_TIME / pow(1000,4), 3) as SUM_LOCK_TIME_SEC,
  round(QUANTILE_95 / pow(1000,4), 3) as P95,
  round(QUANTILE_99 / pow(1000,4), 3) as P99,
  round(QUANTILE_999 / pow(1000,4), 3) as P999,
  SUM_ERRORS,
  SUM_WARNINGS,
  SUM_ROWS_AFFECTED,
  SUM_ROWS_SENT,
  SUM_ROWS_EXAMINED,
  SUM_CREATED_TMP_DISK_TABLES,
  SUM_CREATED_TMP_TABLES,
  SUM_SELECT_FULL_JOIN,
  SUM_SELECT_FULL_RANGE_JOIN,
  SUM_SELECT_RANGE,
  SUM_SELECT_RANGE_CHECK,
  SUM_SELECT_SCAN,
  SUM_SORT_MERGE_PASSES,
  SUM_SORT_RANGE,
  SUM_SORT_ROWS,
  SUM_SORT_SCAN,
  SUM_NO_INDEX_USED,
  SUM_NO_GOOD_INDEX_USED,
  -- round(SUM_CPU_TIME / pow(1000,4), 3) as SUM_CPU_TIME_SEC,
  round(MAX_CONTROLLED_MEMORY / pow(1024,2), 3) as MAX_CONTROLLED_MEMORY_MB,
  round(MAX_TOTAL_MEMORY / pow(1024,2), 3) as MAX_TOTAL_MEMORY_MB,
  -- COUNT_SECONDARY,
  -- FIRST_SEEN,
  -- LAST_SEEN,
  QUERY_SAMPLE_TEXT,
  -- QUERY_SAMPLE_SEEN,
  round(QUERY_SAMPLE_TIMER_WAIT / pow(1000,4), 3) as QUERY_SAMPLE_TIMER_WAIT_SEC
FROM
  performance_schema.events_statements_summary_by_digest
WHERE
  `SCHEMA_NAME` != 'performance_schema'
  AND `SCHEMA_NAME` IS NOT NULL
ORDER BY
  SUM_TIMER_WAIT desc
LIMIT 20 \G;
