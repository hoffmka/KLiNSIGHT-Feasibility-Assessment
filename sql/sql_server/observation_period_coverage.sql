-- DB observation period coverage
-- Returns one row per observation period start year with person counts,
-- plus a summary row for the full coverage span.

SELECT
  YEAR(observation_period_start_date) AS OBS_START_YEAR,
  MIN(observation_period_start_date)  AS MIN_OBS_START,
  MAX(observation_period_end_date)    AS MAX_OBS_END,
  COUNT(DISTINCT person_id)           AS N_PERSONS,
  AVG(CAST(DATEDIFF(day,
        observation_period_start_date,
        observation_period_end_date) AS FLOAT)) AS AVG_OBS_DAYS
FROM @cdmDatabaseSchema.observation_period
GROUP BY YEAR(observation_period_start_date)
ORDER BY OBS_START_YEAR;
