# ============================================================
# KLiNSIGHT Study Diagnostics
# 2. Cohort entry year plausibility
# ============================================================
#
# Reads the CohortDiagnostics incidence_rate.csv (calendar
# year stratification) and checks whether the temporal
# distribution of KLiNSIGHT cohort entries is plausible.
#
# A suspicious pattern would be, e.g., all KLiNSIGHT patients
# entering in a single year — this may indicate a data quality
# issue or a one-time bulk import rather than continuous data
# capture.
#
# Input:  cohortDiagnosticsDir/incidence_rate.csv
# Output: data.frame row for the diagnostic results CSV
#
# STATUS rules:
#   PASS    — entries spread across ≥ 2 years AND no single
#             year accounts for ≥ 75% of entries
#   WARNING — a single year accounts for ≥ 75% of entries
#             OR entries found in only 1 year
# ============================================================

runKLiNSIGHTCohortEntryYearPlausibility <- function(cohortDiagnosticsDir,
                                                      siteId,
                                                      cohortId  = 1L,
                                                      checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking cohort entry year plausibility...")

  irPath <- file.path(cohortDiagnosticsDir, "incidence_rate.csv")
  if (!file.exists(irPath)) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("incidence_rate.csv not found in ", cohortDiagnosticsDir)
    ))
  }

  ir <- read.csv(irPath, stringsAsFactors = FALSE)
  ir <- ir[ir$cohort_id == cohortId, ]

  # Year-only rows: calendar_year set, gender and age_group blank
  yRows <- ir[
    !is.na(ir$calendar_year) & nchar(trimws(as.character(ir$calendar_year))) > 0 &
    (is.na(ir$gender)    | nchar(trimws(ir$gender))    == 0) &
    (is.na(ir$age_group) | nchar(trimws(ir$age_group)) == 0),
  ]

  # Keep only years with confirmed patients (cohort_count > 0; -5 = suppressed = has patients)
  yRows$year <- as.integer(yRows$calendar_year)
  yWithPts   <- yRows[yRows$cohort_count > 0 | yRows$cohort_count == -5, ]

  if (nrow(yWithPts) == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = "No calendar-year rows with patients in incidence_rate.csv"
    ))
  }

  nYears     <- length(unique(yWithPts$year))
  minYear    <- min(yWithPts$year)
  maxYear    <- max(yWithPts$year)

  # For concentration: use only non-suppressed counts
  knownCounts <- yRows[yRows$cohort_count > 0, ]
  if (nrow(knownCounts) > 0) {
    totalKnown  <- sum(knownCounts$cohort_count)
    maxCount    <- max(knownCounts$cohort_count)
    maxYear_pk  <- knownCounts$year[which.max(knownCounts$cohort_count)]
    maxPct      <- round(maxCount / totalKnown * 100, 1)
  } else {
    # All non-zero counts are suppressed — can't compute concentration
    maxPct     <- NA_real_
    maxYear_pk <- NA_integer_
  }

  status <- dplyr::case_when(
    nYears == 1                          ~ "WARNING",
    !is.na(maxPct) && maxPct >= 75       ~ "WARNING",
    TRUE                                 ~ "PASS"
  )

  msg <- dplyr::case_when(
    nYears == 1 ~
      sprintf("All patients entered cohort in a single year (%d) — possible bulk import or limited data capture",
              minYear),
    !is.na(maxPct) && maxPct >= 75 ~
      sprintf("%.1f%% of patients entered cohort in %d — possible bulk import or data quality issue (range: %d–%d)",
              maxPct, maxYear_pk, minYear, maxYear),
    TRUE ~
      sprintf("Entry years %d–%d across %d years — distribution looks plausible",
              minYear, maxYear, nYears)
  )

  ParallelLogger::logInfo(sprintf("    %s", msg))

  value <- if (!is.na(maxPct)) {
    sprintf("%d–%d (%d years; peak: %d at %.1f%%)", minYear, maxYear, nYears, maxYear_pk, maxPct)
  } else {
    sprintf("%d–%d (%d years; counts suppressed)", minYear, maxYear, nYears)
  }

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
