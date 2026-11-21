# ============================================================
# KLiNSIGHT Study Diagnostics — Entry point
# ============================================================
#
# Runs all study-specific plausibility checks for KLiNSIGHT.
# Checks read from characterization output where possible
# (FeatureExtraction results) rather than querying the DB
# directly — consistent with the OHDSI characterize-first,
# then-check pattern.
#
# Parameters
# ----------
# characterizationDir : folder containing characterization CSVs
# outputFolder        : folder for diagnostic result CSV
# siteId              : site identifier from .env / SITE_ID
# cohortId            : cohort_definition_id for KLiNSIGHT (default 1)
# privacyThreshold    : small-cell suppression threshold (default 5)
# ============================================================

runKLiNSIGHTDiagnostics <- function(characterizationDir,
                                     outputFolder,
                                     siteId,
                                     obsCoverage      = NULL,
                                     cohortId         = 1L,
                                     privacyThreshold = 5L) {

  checkDir <- file.path("R", "StudyDiagnostics", "KLiNSIGHT", "checks")
  for (f in sort(list.files(checkDir, pattern = "\\.R$", full.names = TRUE))) {
    source(f)
  }

  ParallelLogger::logInfo("=== KLiNSIGHT Study Diagnostics ===")

  checkDate <- as.character(Sys.Date())

  checks <- rbind(
    runKLiNSIGHTGenderPlausibility(
      characterizationDir = characterizationDir,
      siteId              = siteId,
      cohortId            = cohortId,
      checkDate           = checkDate
    ),
    runKLiNSIGHTCohortEntryYearPlausibility(
      characterizationDir = characterizationDir,
      obsCoverage         = obsCoverage,
      siteId              = siteId,
      cohortId            = cohortId,
      checkDate           = checkDate
    ),
    runKLiNSIGHTAgeGroupPlausibility(
      characterizationDir = characterizationDir,
      siteId              = siteId,
      cohortId            = cohortId,
      checkDate           = checkDate
    ),
    runKLiNSIGHTIndexDiagnosisDistribution(
      characterizationDir = characterizationDir,
      siteId              = siteId,
      cohortId            = cohortId,
      checkDate           = checkDate
    )
    # Further checks will be added here as they are built
  )

  outFile <- file.path(outputFolder, "INSiGHT_KLiNSIGHT_diagnostics.csv")
  write.csv(checks, outFile, row.names = FALSE)
  ParallelLogger::logInfo(sprintf("KLiNSIGHT diagnostics written to %s", outFile))

  invisible(checks)
}
