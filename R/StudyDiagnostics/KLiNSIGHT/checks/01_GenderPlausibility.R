# ============================================================
# KLiNSIGHT Study Diagnostics
# 1. Gender plausibility
# ============================================================
#
# Reads the CohortDiagnostics incidence_rate.csv (gender
# stratification) and checks whether 100% of KLiNSIGHT
# patients are male.
#
# Klinefelter syndrome (47,XXY) affects exclusively males.
# Any non-male patient indicates a cohort definition problem
# or a data quality issue.
#
# Input:  cohortDiagnosticsDir/incidence_rate.csv
# Output: data.frame row for the diagnostic results CSV
#
# STATUS rules:
#   PASS    — 0 female patients (count = 0)
#   WARNING — female count suppressed (-5); cannot confirm 0
#   FAIL    — ≥ 1 confirmed female patient
# ============================================================

runKLiNSIGHTGenderPlausibility <- function(cohortDiagnosticsDir,
                                            siteId,
                                            cohortId   = 1L,
                                            checkDate  = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking gender plausibility...")

  irPath <- file.path(cohortDiagnosticsDir, "incidence_rate.csv")
  if (!file.exists(irPath)) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("incidence_rate.csv not found in ", cohortDiagnosticsDir)
    ))
  }

  ir <- read.csv(irPath, stringsAsFactors = FALSE)
  ir <- ir[ir$cohort_id == cohortId, ]

  # Gender-only rows: gender set, age_group and calendar_year blank
  gRows <- ir[
    !is.na(ir$gender) & nchar(trimws(ir$gender)) > 0 &
    (is.na(ir$age_group)      | nchar(trimws(ir$age_group))      == 0) &
    (is.na(ir$calendar_year)  | nchar(trimws(ir$calendar_year))  == 0),
  ]

  if (nrow(gRows) == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = "No gender-stratified rows in incidence_rate.csv"
    ))
  }

  # Exclude "No matching concept" (unmapped gender) from pass/fail logic
  female  <- gRows[trimws(gRows$gender) == "Female", ]
  male    <- gRows[trimws(gRows$gender) == "Male",   ]

  nFemale <- if (nrow(female) > 0) female$cohort_count[1] else 0L
  nMale   <- if (nrow(male)   > 0) male$cohort_count[1]   else 0L

  # nFemale == -5 means suppressed (1–4 females present)
  status <- dplyr::case_when(
    nFemale == 0  ~ "PASS",
    nFemale == -5 ~ "WARNING",
    TRUE          ~ "FAIL"
  )

  msg <- dplyr::case_when(
    nFemale == 0  ~ sprintf("0 female patients — consistent with KS (47,XXY); %d male", nMale),
    nFemale == -5 ~ "Female count suppressed (1–4 patients) — cannot confirm 0 females; check source data",
    TRUE          ~ sprintf("%d female patient(s) confirmed — cohort definition or data quality problem", nFemale)
  )

  ParallelLogger::logInfo(sprintf("    %s", msg))

  data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = status,
    VALUE       = sprintf("Female: %s, Male: %d",
                          ifelse(nFemale == -5, "<5", as.character(nFemale)), nMale),
    MESSAGE     = msg
  )
}
