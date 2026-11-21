# ============================================================
# Study-agnostic diagnostic
# 3. Observation period coverage
# ============================================================
#
# Queries observation_period to determine what time span the
# database actually covers and how many persons have records.
# This metadata is used downstream by study-specific
# plausibility checks (e.g. cohort entry year distribution).
#
# Output rows
# -----------
#   DB_OBSERVATION_PERIOD_SPAN  — earliest start to latest end date
#   DB_N_PERSONS_WITH_OBS       — total distinct persons in observation_period
#   DB_DATA_GAPS                — years with < 10% of median person count
#
# STATUS rules
#   DB_OBSERVATION_PERIOD_SPAN
#     PASS    — coverage ≥ 2 years
#     WARNING — coverage < 2 years
#     FAIL    — no rows in observation_period
#   DB_DATA_GAPS
#     PASS    — no year (excl. current) below 10% of median N_PERSONS
#     WARNING — one or more gap years detected
# ============================================================

runObservationPeriodCoverageCheck <- function(connection,
                                               cdmDatabaseSchema,
                                               outputFolder,
                                               siteId) {

  sqlDir    <- file.path("sql", "sql_server")
  checkDate <- as.character(Sys.Date())

  ParallelLogger::logInfo("Running observation period coverage check...")

  res <- executeQuery(
    sqlFilePath       = file.path(sqlDir, "observation_period_coverage.sql"),
    connection        = connection,
    outputFolder      = outputFolder,
    successMessage    = "Observation period coverage",
    cdmDatabaseSchema = cdmDatabaseSchema
  )$result

  if (is.null(res) || nrow(res) == 0) {
    checks <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "DB_OBSERVATION_PERIOD_COVERAGE",
      CHECK_LEVEL = "METADATA",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = "No rows found in observation_period table"
    )
    return(list(checks = checks, obsCoverage = NULL))
  }

  minDate   <- min(as.Date(res$MIN_OBS_START), na.rm = TRUE)
  maxDate   <- max(as.Date(res$MAX_OBS_END),   na.rm = TRUE)
  minYear   <- as.integer(format(minDate, "%Y"))
  maxYear   <- as.integer(format(maxDate, "%Y"))
  spanYears <- maxYear - minYear + 1
  nPersons  <- sum(res$N_PERSONS, na.rm = TRUE)   # summed across start-year groups

  status <- if (spanYears < 2) "WARNING" else "PASS"
  span   <- sprintf("%s — %s (%d calendar year%s)",
                    format(minDate, "%Y-%m-%d"),
                    format(maxDate, "%Y-%m-%d"),
                    spanYears,
                    if (spanYears == 1) "" else "s")

  ParallelLogger::logInfo(sprintf("  DB coverage: %s", span))
  ParallelLogger::logInfo(sprintf("  Persons with observation period: %d", nPersons))

  checks <- rbind(
    data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "DB_OBSERVATION_PERIOD_SPAN",
      CHECK_LEVEL = "METADATA",
      STATUS      = status,
      VALUE       = span,
      MESSAGE     = sprintf("Observation period data from %s to %s",
                            format(minDate, "%Y-%m-%d"), format(maxDate, "%Y-%m-%d"))
    ),
    data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "DB_N_PERSONS_WITH_OBS",
      CHECK_LEVEL = "METADATA",
      STATUS      = "PASS",
      VALUE       = as.character(nPersons),
      MESSAGE     = sprintf("%d distinct persons have at least one observation period", nPersons)
    )
  )

  # --- Gap detection --------------------------------------------------
  # Build a complete year sequence; fill missing years with N_PERSONS = 0.
  # A year is a "gap" if its person count is < 10% of the median across
  # all years in the DB range.
  # The current (most recent) year is excluded: it may be incomplete.
  currentYear  <- as.integer(format(Sys.Date(), "%Y"))
  allYears     <- data.frame(OBS_START_YEAR = seq(minYear, maxYear))
  byYearFull   <- merge(allYears, res[, c("OBS_START_YEAR", "N_PERSONS")],
                        by = "OBS_START_YEAR", all.x = TRUE)
  byYearFull$N_PERSONS[is.na(byYearFull$N_PERSONS)] <- 0L

  # Exclude the current year from gap analysis
  byYearAnalysis <- byYearFull[byYearFull$OBS_START_YEAR < currentYear, ]

  gapCheck <- if (nrow(byYearAnalysis) < 2) {
    # Too few years to judge
    data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "DB_DATA_GAPS",
      CHECK_LEVEL = "METADATA",
      STATUS      = "PASS",
      VALUE       = "0 gaps",
      MESSAGE     = "Insufficient year range to assess data gaps"
    )
  } else {
    medianPersons <- median(byYearAnalysis$N_PERSONS)
    threshold     <- 0.10 * medianPersons
    gapYears      <- byYearAnalysis$OBS_START_YEAR[byYearAnalysis$N_PERSONS < threshold]

    if (length(gapYears) == 0) {
      ParallelLogger::logInfo("  No data gaps detected in observation period coverage")
      data.frame(
        SITE_ID     = siteId,
        CHECK_DATE  = checkDate,
        CHECK_NAME  = "DB_DATA_GAPS",
        CHECK_LEVEL = "METADATA",
        STATUS      = "PASS",
        VALUE       = "0 gaps",
        MESSAGE     = sprintf(
          "No years with <10%% of median person count (%d) detected within %d–%d",
          round(medianPersons), minYear, maxYear - 1
        )
      )
    } else {
      gapStr <- paste(gapYears, collapse = ", ")
      ParallelLogger::logWarn(sprintf("  Data gaps detected: %s", gapStr))
      data.frame(
        SITE_ID     = siteId,
        CHECK_DATE  = checkDate,
        CHECK_NAME  = "DB_DATA_GAPS",
        CHECK_LEVEL = "METADATA",
        STATUS      = "WARNING",
        VALUE       = sprintf("%d gap%s: %s",
                              length(gapYears),
                              if (length(gapYears) == 1) "" else "s",
                              gapStr),
        MESSAGE     = sprintf(
          "Years with <10%% of median person count (%d) within %d–%d: %s",
          round(medianPersons), minYear, maxYear - 1, gapStr
        )
      )
    }
  }

  checks <- rbind(checks, gapCheck)

  # Return coverage metadata for use by downstream checks
  obsCoverage <- list(
    minDate   = minDate,
    maxDate   = maxDate,
    minYear   = minYear,
    maxYear   = maxYear,
    spanYears = spanYears,
    byYear    = byYearFull   # full per-year breakdown (0-filled)
  )

  list(checks = checks, obsCoverage = obsCoverage)
}
