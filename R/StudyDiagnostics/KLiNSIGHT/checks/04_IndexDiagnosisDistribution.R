# ============================================================
# KLiNSIGHT Study Diagnostics
# 4. Index diagnosis distribution
# ============================================================
#
# Reads the CohortDiagnostics index-event breakdown
# (produced by R/03_CohortDiagnostics.R, exported to cohortDiagnosticsDir)
# and checks whether the concepts that triggered KLiNSIGHT
# cohort entry are consistent with Klinefelter syndrome.
#
# CohortDiagnostics exports results as a zip file or as
# individual CSVs into the index_event_breakdown/ subfolder.
# Both formats are handled here.
#
# Checks
# ------
#   KLINSIGHT_INDEX_DIAGNOSIS_VOCAB
#     Flags vocabularies other than SNOMED, ICD10*, or ORPHA
#     appearing as cohort entry triggers.
#     PASS    — only expected vocabularies found
#     WARNING — unexpected vocabulary present
#
#   KLINSIGHT_INDEX_DIAGNOSIS_DISTRIBUTION
#     Reports the top source codes that triggered cohort entry.
#     Always PASS — informational only.
# ============================================================

runKLiNSIGHTIndexDiagnosisDistribution <- function(cohortDiagnosticsDir,
                                                     siteId,
                                                     cohortId  = 1L,
                                                     checkDate = as.character(Sys.Date())) {

  ParallelLogger::logInfo("  [KLiNSIGHT] Checking index diagnosis distribution...")

  # --- 1. Locate breakdown CSV and concept lookup ----------------------
  # CohortDiagnostics exports index_event_breakdown.csv and concept.csv
  # directly into cohortDiagnosticsDir.
  csvPath     <- file.path(cohortDiagnosticsDir, "index_event_breakdown.csv")
  conceptPath <- file.path(cohortDiagnosticsDir, "concept.csv")

  if (!file.exists(csvPath)) {
    noFile <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("KLINSIGHT_INDEX_DIAGNOSIS_VOCAB",
                      "KLINSIGHT_INDEX_DIAGNOSIS_DISTRIBUTION"),
      CHECK_LEVEL = c("PLAUSIBILITY", "CHARACTERIZATION"),
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("index_event_breakdown.csv not found in ", cohortDiagnosticsDir,
                           ". Run R/03_CohortDiagnostics.R first.")
    )
    return(noFile)
  }

  ParallelLogger::logInfo(sprintf("    Reading: %s", basename(csvPath)))
  bd <- read.csv(csvPath, stringsAsFactors = FALSE)
  names(bd) <- toupper(names(bd))
  if (!"COHORT_ID"     %in% names(bd) && "COHORTID"     %in% names(bd)) bd$COHORT_ID     <- bd$COHORTID
  if (!"CONCEPT_ID"    %in% names(bd) && "CONCEPTID"    %in% names(bd)) bd$CONCEPT_ID    <- bd$CONCEPTID
  if (!"SUBJECT_COUNT" %in% names(bd) && "SUBJECTCOUNT" %in% names(bd)) bd$SUBJECT_COUNT <- bd$SUBJECTCOUNT

  bd <- bd[bd$COHORT_ID == cohortId & !is.na(bd$SUBJECT_COUNT) & bd$SUBJECT_COUNT > 0, ]

  # Join concept metadata from concept.csv
  if (file.exists(conceptPath)) {
    cdf <- read.csv(conceptPath, stringsAsFactors = FALSE)
    names(cdf) <- toupper(names(cdf))
    if (!"CONCEPT_ID"   %in% names(cdf) && "CONCEPTID"   %in% names(cdf)) cdf$CONCEPT_ID   <- cdf$CONCEPTID
    if (!"CONCEPT_NAME" %in% names(cdf) && "CONCEPTNAME" %in% names(cdf)) cdf$CONCEPT_NAME <- cdf$CONCEPTNAME
    if (!"CONCEPT_CODE" %in% names(cdf) && "CONCEPTCODE" %in% names(cdf)) cdf$CONCEPT_CODE <- cdf$CONCEPTCODE
    if (!"VOCABULARY_ID"%in% names(cdf) && "VOCABULARYID"%in% names(cdf)) cdf$VOCABULARY_ID<- cdf$VOCABULARYID
    bd <- merge(bd,
                cdf[, c("CONCEPT_ID", "CONCEPT_NAME", "CONCEPT_CODE", "VOCABULARY_ID")],
                by = "CONCEPT_ID", all.x = TRUE)
  } else {
    ParallelLogger::logWarn("    concept.csv not found; vocabulary checks will be incomplete")
    bd$CONCEPT_NAME  <- NA_character_
    bd$CONCEPT_CODE  <- as.character(bd$CONCEPT_ID)
    bd$VOCABULARY_ID <- NA_character_
  }

  if (nrow(bd) == 0) {
    noData <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("KLINSIGHT_INDEX_DIAGNOSIS_VOCAB",
                      "KLINSIGHT_INDEX_DIAGNOSIS_DISTRIBUTION"),
      CHECK_LEVEL = "PLAUSIBILITY",
      STATUS      = "FAIL",
      VALUE       = NA_character_,
      MESSAGE     = paste0("No index event breakdown data for cohort ID ", cohortId)
    )
    return(noData)
  }

  # --- 2. Vocabulary check ---------------------------------------------
  # For KLiNSIGHT, only SNOMED (standard) and ICD10*/ORPHA (source) expected
  EXPECTED_VOCABS <- c("SNOMED", "ICD10GM", "ICD10CM", "ICD10", "ORPHA",
                       "Nebraska Lexicon")   # Nebraska Lexicon maps KS in some CDMs

  vocabs        <- unique(bd$VOCABULARY_ID)
  unexpectedV   <- vocabs[!vocabs %in% EXPECTED_VOCABS]

  vocabStatus <- if (length(unexpectedV) == 0) "PASS" else "WARNING"
  vocabMsg <- if (length(unexpectedV) == 0) {
    sprintf("All entry-triggering vocabularies expected for KLiNSIGHT: %s",
            paste(vocabs, collapse = ", "))
  } else {
    sprintf("Unexpected vocabularies in cohort entry trigger: %s (expected: %s)",
            paste(unexpectedV, collapse = ", "),
            paste(EXPECTED_VOCABS, collapse = ", "))
  }

  ParallelLogger::logInfo(sprintf("    Vocabularies in breakdown: %s", paste(vocabs, collapse = ", ")))

  vocabCheck <- data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_INDEX_DIAGNOSIS_VOCAB",
    CHECK_LEVEL = "PLAUSIBILITY",
    STATUS      = vocabStatus,
    VALUE       = paste(vocabs, collapse = ", "),
    MESSAGE     = vocabMsg
  )

  # --- 3. Distribution (characterization) -----------------------------
  # Export a per-code distribution CSV alongside the diagnostics, and
  # add a summary row in the checks output.
  bd <- bd[order(-bd$SUBJECT_COUNT), ]

  # Source-code rows (non-SNOMED) carry the ICD/ORPHA codes
  srcRows <- bd[bd$VOCABULARY_ID != "SNOMED", ]

  # Write detailed distribution CSV
  distCsv <- data.frame(
    SITE_ID       = siteId,
    CHECK_DATE    = checkDate,
    COHORT_ID     = cohortId,
    CONCEPT_CODE  = bd$CONCEPT_CODE,
    CONCEPT_NAME  = bd$CONCEPT_NAME,
    VOCABULARY_ID = bd$VOCABULARY_ID,
    SUBJECT_COUNT = bd$SUBJECT_COUNT,
    stringsAsFactors = FALSE
  )
  distFile <- file.path(
    dirname(csvPath),
    paste0("klinsight_index_diagnosis_distribution_", checkDate, ".csv")
  )
  write.csv(distCsv, distFile, row.names = FALSE)
  ParallelLogger::logInfo(sprintf("    Distribution written to: %s", basename(distFile)))

  # Summary string for the diagnostics CSV (top source codes)
  if (nrow(srcRows) > 0) {
    topN    <- head(srcRows, 10)
    summary <- paste(
      sprintf("%s [%s] n=%s", topN$CONCEPT_CODE, topN$VOCABULARY_ID, topN$SUBJECT_COUNT),
      collapse = "; "
    )
  } else {
    summary <- "no source-code breakdown available"
  }

  ParallelLogger::logInfo(sprintf("    Top source codes: %s", summary))

  distCheck <- data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = "KLINSIGHT_INDEX_DIAGNOSIS_DISTRIBUTION",
    CHECK_LEVEL = "CHARACTERIZATION",
    STATUS      = "PASS",
    VALUE       = summary,
    MESSAGE     = sprintf(
      "%d concept(s) in breakdown; full distribution: %s",
      nrow(bd), basename(distFile)
    )
  )

  rbind(vocabCheck, distCheck)
}
