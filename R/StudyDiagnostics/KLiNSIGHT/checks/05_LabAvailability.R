# ============================================================
# KLiNSIGHT Study Diagnostics
# 5. Key lab availability (mapped OMOP concepts)
# ============================================================
#
# Checks whether the diagnostic labs for Klinefelter syndrome
# are available as mapped OMOP measurement concepts for the
# KLiNSIGHT cohort.
#
# Key labs:
#   Essential (required for KS diagnosis/monitoring):
#     • Testosterone (total / free)      — LOINC 2986-8 / 2991-8
#     • Follitropin (FSH)                — LOINC 15067-2
#     • Lutropin (LH)                    — LOINC 10501-5
#   Informative (common comorbidity screening):
#     • Thyrotropin (TSH)                — LOINC 3016-3
#
# Source: temporal_covariate_ref.csv + temporal_covariate_value.csv
# (time_id = 10: entire observation period — maximises detectable coverage)
#
# IMPORTANT — mapped vs. unmapped:
#   This check detects only labs that are mapped to standard OMOP
#   measurement concepts (concept_id > 0). If a lab is absent here
#   but expected at the site, the measurement may exist in the
#   source system with concept_id = 0 (unmapped). To investigate,
#   query your measurement table for source_value patterns such as
#   "TESTO", "FSH", "LH", "TSH" where measurement_concept_id = 0.
#
# STATUS rules:
#   PASS    — all 3 essential labs (Testosterone, FSH, LH) found
#             with detectable coverage (mean > 0 for at least one
#             cohort_id row)
#   WARNING — 1–2 essential labs found with detectable coverage,
#             OR all 3 found but all counts are suppressed
#   FAIL    — none of the essential labs detected at all
# ============================================================

runKLiNSIGHTLabAvailability <- function(cohortDiagnosticsDir,
                                          siteId,
                                          cohortId  = 1L,
                                          timeId    = 10L,
                                          checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking key lab availability...")

  refPath <- file.path(cohortDiagnosticsDir, "temporal_covariate_ref.csv")
  valPath <- file.path(cohortDiagnosticsDir, "temporal_covariate_value.csv")

  if (!file.exists(refPath) || !file.exists(valPath)) {
    missing <- paste(c(
      if (!file.exists(refPath)) "temporal_covariate_ref.csv",
      if (!file.exists(valPath)) "temporal_covariate_value.csv"
    ), collapse = ", ")
    return(data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "KLINSIGHT_LAB_AVAILABILITY",
      CHECK_LEVEL = "COMPLETENESS",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("Required file(s) not found: ", missing,
                           " — ensure runTemporalCohortCharacterization = TRUE in CohortDiagnostics settings")
    ))
  }

  ref <- read.csv(refPath, stringsAsFactors = FALSE)
  val <- read.csv(valPath, stringsAsFactors = FALSE)

  # Join covariate names into values
  dat <- merge(val, ref[, c("covariate_id", "covariate_name", "analysis_id")],
               by = "covariate_id", all.x = FALSE)

  # Restrict to cohort, time window, and analysis_id = 701 (measurement presence)
  dat <- dat[dat$cohort_id  == cohortId &
             dat$time_id    == timeId   &
             dat$analysis_id == 701, ]

  # ---- Target lab groups ------------------------------------------------
  labs <- list(
    list(label    = "Testosterone",
         pattern  = "testoster",
         essential = TRUE),
    list(label    = "FSH (Follitropin)",
         pattern  = "follitrop",
         essential = TRUE),
    list(label    = "LH (Lutropin)",
         pattern  = "lutrop",
         essential = TRUE),
    list(label    = "TSH (Thyrotropin)",
         pattern  = "thyrotropin",
         essential = FALSE)
  )

  # ---- Evaluate each lab ------------------------------------------------
  results <- lapply(labs, function(lab) {
    rows <- dat[grepl(lab$pattern, dat$covariate_name, ignore.case = TRUE), ]
    if (nrow(rows) == 0) {
      return(list(label = lab$label, essential = lab$essential,
                  found = FALSE, suppressed = FALSE, maxMean = NA_real_,
                  covNames = character(0)))
    }
    # sum_value > 0 → confirmed patients; sum_value == -5 → suppressed
    hasPatients  <- any(rows$sum_value > 0)
    isSuppressed <- !hasPatients && any(rows$sum_value == -5)
    maxMean      <- if (hasPatients) max(rows$mean[rows$sum_value > 0]) else NA_real_
    list(label     = lab$label,
         essential  = lab$essential,
         found      = hasPatients || isSuppressed,
         suppressed = isSuppressed && !hasPatients,
         maxMean    = maxMean,
         covNames   = rows$covariate_name[rows$sum_value > 0 | rows$sum_value == -5])
  })

  # ---- Summarise --------------------------------------------------------
  essential <- Filter(function(x) x$essential, results)
  nFound        <- sum(sapply(essential, function(x) x$found))
  nFoundClear   <- sum(sapply(essential, function(x) x$found & !x$suppressed))
  allSuppressed <- nFound == length(essential) && nFoundClear == 0

  status <- dplyr::case_when(
    nFound == 0                                       ~ "FAIL",
    nFound < length(essential) | allSuppressed        ~ "WARNING",
    TRUE                                              ~ "PASS"
  )

  # Build per-lab summary string
  labSummary <- sapply(results, function(x) {
    if (!x$found) {
      sprintf("%s: NOT FOUND", x$label)
    } else if (x$suppressed) {
      sprintf("%s: present (suppressed, n < threshold)", x$label)
    } else {
      sprintf("%s: %.0f%% of patients", x$label, x$maxMean * 100)
    }
  })
  value <- paste(labSummary, collapse = " | ")

  msg <- dplyr::case_when(
    nFound == 0 ~
      paste0("None of the essential KS labs (Testosterone, FSH, LH) found as mapped OMOP concepts. ",
             "Check measurement_concept_id = 0 entries in the measurement table for unmapped source codes."),
    allSuppressed ~
      paste0("All essential labs found but counts are suppressed (< privacyThreshold). ",
             "Coverage cannot be quantified; verify mapping quality."),
    nFound < length(essential) ~ {
      missing_labs <- sapply(Filter(function(x) x$essential & !x$found, results), `[[`, "label")
      paste0("Missing essential lab(s): ", paste(missing_labs, collapse = ", "),
             ". If expected at this site, check for unmapped source codes (measurement_concept_id = 0).")
    },
    TRUE ~
      paste0("All essential labs mapped and available. ", value)
  )

  ParallelLogger::logInfo(sprintf("    Status: %s", status))
  for (l in labSummary) ParallelLogger::logInfo(sprintf("      %s", l))

  data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_LAB_AVAILABILITY",
    CHECK_LEVEL = "COMPLETENESS",
    STATUS      = status,
    VALUE       = value,
    MESSAGE     = msg
  )
}
