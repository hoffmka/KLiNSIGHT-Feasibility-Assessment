# ============================================================
# KLiNSIGHT Study Diagnostics
# 3. Age group plausibility
# ============================================================
#
# Reads the age group characterization (produced by
# R/Characterization/01_Demographics.R) and checks whether
# the age distribution at cohort start is plausible for
# Klinefelter syndrome (47,XXY).
#
# KS is typically diagnosed between ages 10 and 64:
#   - Adolescence: delayed puberty / developmental concerns
#   - Adulthood: infertility workup
#   - Neonatal / very late diagnoses are rare in most EHR settings
#
# Checks
# ------
#   KLINSIGHT_AGE_CORE_WINDOW
#     Proportion of patients with cohort start in ages 10–64.
#     PASS    — ≥ 50% in core window
#     WARNING — < 50% in core window (unusual distribution)
#
#   KLINSIGHT_AGE_CONCENTRATION
#     Whether any single 5-year band dominates the cohort.
#     PASS    — no band ≥ 50%
#     WARNING — one band ≥ 50% (possible coding anomaly)
# ============================================================

runKLiNSIGHTAgeGroupPlausibility <- function(characterizationDir,
                                               siteId,
                                               cohortId  = 1L,
                                               checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking age group plausibility...")

  # --- 1. Load characterization CSV ------------------------------------
  ageFiles <- list.files(
    characterizationDir,
    pattern    = "^age_groups_.*\\.csv$",
    full.names = TRUE
  )

  if (length(ageFiles) == 0) {
    noFile <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("KLINSIGHT_AGE_CORE_WINDOW", "KLINSIGHT_AGE_CONCENTRATION"),
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("Age group file not found in ", characterizationDir,
                           ". Run R/Characterization/01_Demographics.R first.")
    )
    return(noFile)
  }

  ageFile <- ageFiles[order(ageFiles, decreasing = TRUE)][1]
  ParallelLogger::logInfo(sprintf("    Reading: %s", basename(ageFile)))

  ages <- read.csv(ageFile, stringsAsFactors = FALSE)
  ages <- ages[ages$cohortId == cohortId, ]

  if (nrow(ages) == 0) {
    noData <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("KLINSIGHT_AGE_CORE_WINDOW", "KLINSIGHT_AGE_CONCENTRATION"),
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("No age group data for cohort ID ", cohortId)
    )
    return(noData)
  }

  # --- 2. Parse age bands from covariateName ---------------------------
  # covariateName looks like: "age group: 10 - 14"
  ages$ageStart <- suppressWarnings(
    as.integer(gsub(".*age group:\\s*(\\d+)\\s*-.*", "\\1", ages$covariateName,
                    ignore.case = TRUE))
  )
  ages$ageEnd <- suppressWarnings(
    as.integer(gsub(".*age group:\\s*\\d+\\s*-\\s*(\\d+).*", "\\1", ages$covariateName,
                    ignore.case = TRUE))
  )

  ages <- ages[!is.na(ages$ageStart), ]

  if (nrow(ages) == 0) {
    parseErr <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("KLINSIGHT_AGE_CORE_WINDOW", "KLINSIGHT_AGE_CONCENTRATION"),
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("Could not parse age group bands from covariateName: ",
                           paste(head(ages$covariateName, 3), collapse = "; "))
    )
    return(parseErr)
  }

  # --- 3. Core window check --------------------------------------------
  # Core diagnostic window for KS: ages 10–64
  CORE_MIN <- 10L
  CORE_MAX <- 64L

  coreRows    <- ages[ages$ageStart >= CORE_MIN & ages$ageStart <= CORE_MAX, ]
  corePct     <- sum(coreRows$percentage, na.rm = TRUE)

  youngRows   <- ages[ages$ageStart < CORE_MIN, ]
  youngPct    <- sum(youngRows$percentage, na.rm = TRUE)
  oldRows     <- ages[ages$ageStart > CORE_MAX, ]
  oldPct      <- sum(oldRows$percentage, na.rm = TRUE)

  coreStatus <- if (corePct >= 50) "PASS" else "WARNING"

  coreMsg <- if (corePct >= 50) {
    sprintf(
      "%.1f%% of patients in core diagnostic window (%d–%d); young (<10): %.1f%%, older (>64): %.1f%%",
      corePct, CORE_MIN, CORE_MAX, youngPct, oldPct
    )
  } else {
    sprintf(
      "Only %.1f%% of patients in core diagnostic window (%d–%d) — young (<10): %.1f%%, older (>64): %.1f%%; distribution unusual for KS",
      corePct, CORE_MIN, CORE_MAX, youngPct, oldPct
    )
  }

  ParallelLogger::logInfo(sprintf("    Core window %d–%d: %.1f%%", CORE_MIN, CORE_MAX, corePct))

  coreCheck <- data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_AGE_CORE_WINDOW",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = coreStatus,
    VALUE       = sprintf("%.1f%% in %d–%d", corePct, CORE_MIN, CORE_MAX),
    MESSAGE     = coreMsg
  )

  # --- 4. Concentration check ------------------------------------------
  maxBandPct  <- max(ages$percentage, na.rm = TRUE)
  maxBandIdx  <- which.max(ages$percentage)
  maxBandName <- ages$covariateName[maxBandIdx]

  concStatus <- if (maxBandPct >= 50) "WARNING" else "PASS"

  concMsg <- if (maxBandPct >= 50) {
    sprintf(
      "%.1f%% of patients concentrated in a single age band ('%s') — possible coding or data quality issue",
      maxBandPct, maxBandName
    )
  } else {
    sprintf(
      "No single age band dominates; peak band '%s' has %.1f%%",
      maxBandName, maxBandPct
    )
  }

  ParallelLogger::logInfo(sprintf("    Peak age band: '%s' at %.1f%%", maxBandName, maxBandPct))

  concCheck <- data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_AGE_CONCENTRATION",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = concStatus,
    VALUE       = sprintf("peak: '%s' at %.1f%%", maxBandName, maxBandPct),
    MESSAGE     = concMsg
  )

  rbind(coreCheck, concCheck)
}
