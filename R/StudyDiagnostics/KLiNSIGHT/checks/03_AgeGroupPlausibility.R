# ============================================================
# KLiNSIGHT Study Diagnostics
# 3. Age group plausibility
# ============================================================
#
# Reads the CohortDiagnostics incidence_rate.csv (age group
# stratification) and checks whether the age distribution of
# KLiNSIGHT cohort entries is plausible.
#
# Klinefelter syndrome (47,XXY) has two clinical presentation
# peaks:
#   • 10–19 years: delayed puberty / hypogonadism work-up
#   • 30–39 years: fertility / infertility investigation
#
# Any patients in the 0–9 age bin are unexpected and trigger
# a WARNING (premature diagnosis without clear indication).
#
# Input:  cohortDiagnosticsDir/incidence_rate.csv
# Output: data.frame row for the diagnostic results CSV
#
# CohortDiagnostics age_group format: "0-9", "10-19", ... "80-89"
#
# STATUS rules:
#   PASS    — expected distribution: 10–19 and/or 30–39
#             are the two largest bins; <5% in 0–9
#   WARNING — 0–9 bin contains patients (unusual early Dx),
#             OR the peak bin is entirely outside 10–64 range,
#             OR only 1 bin has patients (insufficient spread)
# ============================================================

runKLiNSIGHTAgeGroupPlausibility <- function(cohortDiagnosticsDir,
                                               siteId,
                                               cohortId  = 1L,
                                               checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking age group plausibility...")

  irPath <- file.path(cohortDiagnosticsDir, "incidence_rate.csv")
  if (!file.exists(irPath)) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_AGE_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("incidence_rate.csv not found in ", cohortDiagnosticsDir)
    ))
  }

  ir <- read.csv(irPath, stringsAsFactors = FALSE)
  ir <- ir[ir$cohort_id == cohortId, ]

  # Age-only rows: age_group set, gender and calendar_year blank
  aRows <- ir[
    !is.na(ir$age_group) & nchar(trimws(as.character(ir$age_group))) > 0 &
    (is.na(ir$gender)        | nchar(trimws(ir$gender))        == 0) &
    (is.na(ir$calendar_year) | nchar(trimws(as.character(ir$calendar_year))) == 0),
  ]

  # Keep only rows with patients (cohort_count > 0 or suppressed)
  aWithPts <- aRows[aRows$cohort_count > 0 | aRows$cohort_count == -5, ]

  if (nrow(aWithPts) == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_AGE_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = "No age-group rows with patients in incidence_rate.csv"
    ))
  }

  # Parse age group lower bound for ordering ("10-19" → 10)
  aWithPts$age_lower <- suppressWarnings(
    as.integer(sub("^(\\d+).*", "\\1", aWithPts$age_group))
  )
  aWithPts <- aWithPts[order(aWithPts$age_lower), ]

  binsPresent <- paste(sort(unique(aWithPts$age_group)), collapse = ", ")
  nBins       <- length(unique(aWithPts$age_lower))

  # Check 0–9 bin
  has0_9 <- any(aWithPts$age_lower == 0)

  # Peak bin from non-suppressed rows
  knownCounts <- aWithPts[aWithPts$cohort_count > 0, ]
  if (nrow(knownCounts) > 0) {
    peakIdx       <- which.max(knownCounts$cohort_count)
    peakBin       <- knownCounts$age_group[peakIdx]
    peakLower     <- knownCounts$age_lower[peakIdx]
    peakCount     <- knownCounts$cohort_count[peakIdx]
    total         <- sum(knownCounts$cohort_count)
    pct0_9        <- if (has0_9) {
      n0_9 <- sum(knownCounts$cohort_count[knownCounts$age_lower == 0], na.rm = TRUE)
      round(n0_9 / total * 100, 1)
    } else { 0 }
    peakInRange   <- peakLower >= 10 & peakLower <= 64   # 10–19 through 60–69 expected
  } else {
    # All non-zero suppressed
    peakBin     <- NA_character_
    peakLower   <- NA_integer_
    peakCount   <- NA_integer_
    pct0_9      <- NA_real_
    peakInRange <- NA
  }

  status <- dplyr::case_when(
    has0_9 & !is.na(pct0_9) & pct0_9 >= 5                ~ "WARNING",
    has0_9                                                  ~ "WARNING",
    nBins == 1                                              ~ "WARNING",
    !is.na(peakInRange) && !peakInRange                    ~ "WARNING",
    TRUE                                                    ~ "PASS"
  )

  msg <- dplyr::case_when(
    has0_9 & !is.na(pct0_9) & pct0_9 >= 5 ~
      sprintf("%.1f%% of patients entered in age group 0-9 — unexpectedly early Klinefelter diagnosis; bins present: %s",
              pct0_9, binsPresent),
    has0_9 ~
      sprintf("Patients present in age group 0-9 (count suppressed) — verify coding; bins: %s", binsPresent),
    nBins == 1 ~
      sprintf("Patients confined to a single age group (%s) — insufficient age spread", binsPresent),
    !is.na(peakInRange) && !peakInRange ~
      sprintf("Peak age group %s is outside expected 10–64 range; bins: %s", peakBin, binsPresent),
    !is.na(peakBin) ~
      sprintf("Peak age group: %s — consistent with expected KS presentation (10–19 puberty or 30–39 fertility); bins: %s",
              peakBin, binsPresent),
    TRUE ~
      sprintf("Age groups (counts suppressed): %s", binsPresent)
  )

  ParallelLogger::logInfo(sprintf("    %s", msg))

  value <- if (!is.na(peakBin)) {
    sprintf("peak=%s; bins=%s", peakBin, binsPresent)
  } else {
    sprintf("bins=%s (counts suppressed)", binsPresent)
  }

  data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_AGE_PLAUSIBILITY",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = status,
    VALUE       = value,
    MESSAGE     = msg
  )
}
