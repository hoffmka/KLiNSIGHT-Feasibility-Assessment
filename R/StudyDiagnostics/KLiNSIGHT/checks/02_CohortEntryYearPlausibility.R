# ============================================================
# KLiNSIGHT Study Diagnostics
# 2. Cohort entry year plausibility
# ============================================================
#
# Reads the cohort entry year characterization (produced by
# R/Characterization/02_CohortEntryYear.R) and the DB
# observation period coverage (from study-agnostic diagnostics)
# and checks whether the temporal distribution of KLiNSIGHT
# cohort entries is plausible.
#
# A suspicious pattern would be, e.g., a database with records
# from 2015 onwards where all KLiNSIGHT patients have cohort
# entry year 2020 — this may indicate a data quality issue or
# a one-time bulk import rather than continuous data capture.
#
# Input
# -----
#   characterizationDir/cohort_entry_year_<date>.csv
#   studyAgnosticResults$obsCoverage  (minYear, maxYear, spanYears)
#
# STATUS rules
# ------------
#   PASS    — entries spread across ≥ 50% of *active* DB years
#             AND no single year accounts for ≥ 75% of entries
#   WARNING — a single year accounts for ≥ 75% of entries
#             OR entries cover < 50% of active DB years
#
# Active DB years = years where N_PERSONS ≥ 10% of median
# (same threshold as DB_DATA_GAPS; early thin-record years excluded)
# ============================================================

runKLiNSIGHTCohortEntryYearPlausibility <- function(characterizationDir,
                                                      obsCoverage,
                                                      siteId,
                                                      cohortId  = 1L,
                                                      checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking cohort entry year plausibility...")

  # --- 1. Load characterization CSV ------------------------------------
  entryFiles <- list.files(
    characterizationDir,
    pattern    = "^cohort_entry_year_.*\\.csv$",
    full.names = TRUE
  )

  if (length(entryFiles) == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("Cohort entry year file not found in ", characterizationDir,
                           ". Run R/Characterization/02_CohortEntryYear.R first.")
    ))
  }

  entryFile <- entryFiles[order(entryFiles, decreasing = TRUE)][1]
  ParallelLogger::logInfo(sprintf("    Reading: %s", basename(entryFile)))

  entries <- read.csv(entryFile, stringsAsFactors = FALSE)
  entries <- entries[entries$cohortId == cohortId, ]

  if (nrow(entries) == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("No cohort entry year data for cohort ID ", cohortId)
    ))
  }

  # --- 2. DB coverage from study-agnostic results ----------------------
  if (is.null(obsCoverage)) {
    dbMinYear      <- min(entries$entryYear)
    dbMaxYear      <- max(entries$entryYear)
    dbSpanYrs      <- dbMaxYear - dbMinYear + 1
    nActiveDbYears <- dbSpanYrs   # no byYear data available
    ParallelLogger::logWarn("    obsCoverage not available; using cohort year range as proxy")
  } else {
    dbMinYear <- obsCoverage$minYear
    dbMaxYear <- obsCoverage$maxYear
    dbSpanYrs <- obsCoverage$spanYears

    # Active years = years with N_PERSONS >= 10% of median (same threshold
    # as DB_DATA_GAPS check). Early years with thin records should not count
    # against the cohort's coverage ratio.
    byYear <- obsCoverage$byYear
    if (!is.null(byYear) && nrow(byYear) > 1) {
      medN           <- median(byYear$N_PERSONS, na.rm = TRUE)
      nActiveDbYears <- sum(byYear$N_PERSONS >= 0.10 * medN, na.rm = TRUE)
    } else {
      nActiveDbYears <- dbSpanYrs
    }
  }

  # --- 3. Cohort entry year metrics ------------------------------------
  cohortMinYear  <- min(entries$entryYear)
  cohortMaxYear  <- max(entries$entryYear)
  nYearsWithData <- length(unique(entries$entryYear))
  maxYearPct     <- max(entries$percentage)
  maxYearVal     <- entries$entryYear[which.max(entries$percentage)]
  pctCoverage    <- round(nYearsWithData / nActiveDbYears * 100, 1)

  # --- 4. Evaluate -----------------------------------------------------
  # Compare against active DB years only (years with ≥ 10% of median
  # N_PERSONS). This avoids penalising the cohort for years when the DB
  # itself had thin data (e.g. the first few years of EHR roll-out).
  status <- dplyr::case_when(
    maxYearPct >= 75                        ~ "WARNING",
    nYearsWithData / nActiveDbYears < 0.50  ~ "WARNING",
    TRUE                                    ~ "PASS"
  )

  msg <- dplyr::case_when(
    maxYearPct >= 75 ~
      sprintf("%.1f%% of patients entered cohort in %d — possible bulk import or data quality issue (active DB: %d–%d)",
              maxYearPct, maxYearVal, dbMinYear, dbMaxYear),
    nYearsWithData / nActiveDbYears < 0.50 ~
      sprintf("Entries span %d of %d active DB years (%d–%d) — %.1f%% coverage; consider investigating gaps",
              nYearsWithData, nActiveDbYears, dbMinYear, dbMaxYear, pctCoverage),
    TRUE ~
      sprintf("Entry years %d–%d span %d of %d active DB years (%d–%d) — %.1f%% coverage; distribution looks plausible",
              cohortMinYear, cohortMaxYear,
              nYearsWithData, nActiveDbYears, dbMinYear, dbMaxYear, pctCoverage)
  )

  ParallelLogger::logInfo(sprintf("    %s", msg))

  value <- sprintf("%d–%d (%d years, %.1f%% of active DB span; peak: %d at %.1f%%)",
                   cohortMinYear, cohortMaxYear,
                   nYearsWithData, pctCoverage,
                   maxYearVal, maxYearPct)

  data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = status,
    VALUE       = value,
    MESSAGE     = msg
  )
}
