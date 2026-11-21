# ============================================================
# KLiNSIGHT Study Diagnostics
# 1. Gender plausibility
# ============================================================
#
# Reads the gender characterization output (produced by
# R/Characterization/03_Gender.R) and checks whether
# 100% of KLiNSIGHT patients are male.
#
# Klinefelter syndrome (47,XXY) affects exclusively males.
# Any non-male patient indicates a cohort definition problem
# or a data quality issue.
#
# Input:  characterizationDir/gender_<date>.csv
# Output: data.frame row for the diagnostic results CSV
#
# STATUS rules:
#   PASS    — 100% male
#   WARNING — ≥95% male (possible miscoding)
#   FAIL    — <95% male
# ============================================================

runKLiNSIGHTGenderPlausibility <- function(characterizationDir,
                                            siteId,
                                            cohortId   = 1L,
                                            checkDate  = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking gender plausibility...")

  # --- 1. Find latest gender characterization file -----------
  genderFiles <- list.files(
    characterizationDir,
    pattern    = "^gender_.*\\.csv$",
    full.names = TRUE
  )

  if (length(genderFiles) == 0) {
    ParallelLogger::logWarn("  No gender characterization file found in: ", characterizationDir)
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("Gender characterization file not found in ", characterizationDir,
                           ". Run R/Characterization/03_Gender.R first.")
    ))
  }

  genderFile <- genderFiles[order(genderFiles, decreasing = TRUE)][1]
  ParallelLogger::logInfo(sprintf("    Reading: %s", basename(genderFile)))

  gender <- read.csv(genderFile, stringsAsFactors = FALSE)
  gender <- gender[gender$cohortId == cohortId, ]

  # --- 2. FeatureExtraction gender concept IDs ---------------
  # covariateId 8507001 = Male (concept 8507)
  # covariateId 8532001 = Female (concept 8532)
  MALE_COVARIATE_ID <- 8507001

  # --- 3. Compute male percentage ----------------------------
  totalPct <- sum(gender$percentage, na.rm = TRUE)   # should sum to ~100

  if (nrow(gender) == 0 || totalPct == 0) {
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = "0",
      MESSAGE     = paste0("No gender data found for cohort ID ", cohortId)
    ))
  }

  malePct <- gender$percentage[gender$covariateId == MALE_COVARIATE_ID]
  malePct <- if (length(malePct) == 0) 0 else malePct[1]

  nMale    <- gender$count[gender$covariateId == MALE_COVARIATE_ID]
  nMale    <- if (length(nMale) == 0) 0L else as.integer(nMale[1])
  nNonMale <- sum(gender$count[gender$covariateId != MALE_COVARIATE_ID], na.rm = TRUE)

  # --- 4. Evaluate -------------------------------------------
  status <- dplyr::case_when(
    malePct == 100  ~ "PASS",
    malePct >= 95   ~ "WARNING",
    TRUE            ~ "FAIL"
  )

  msg <- dplyr::case_when(
    malePct == 100 ~ sprintf("100%% male (%d patients) — consistent with KS (47,XXY)", nMale),
    malePct >= 95  ~ sprintf("%.1f%% male; %d non-male patient(s) — possible miscoding or data issue",
                             malePct, nNonMale),
    TRUE           ~ sprintf("%.1f%% male; %d non-male patient(s) — cohort definition or data quality problem",
                             malePct, nNonMale)
  )

  ParallelLogger::logInfo(sprintf("    %s", msg))

  data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_GENDER_PLAUSIBILITY",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = status,
    VALUE       = sprintf("%.1f%%", malePct),
    MESSAGE     = msg
  )
}
