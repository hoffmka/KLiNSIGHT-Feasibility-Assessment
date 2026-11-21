# ============================================================
# KLiNSIGHT Study Diagnostics — Entry point
# ============================================================
#
# Runs all study-specific plausibility checks for KLiNSIGHT.
# All checks read exclusively from CohortDiagnostics output
# (incidence_rate.csv, cohort_overlap.csv, etc.) — no
# separate characterization run is required.
#
# Parameters
# ----------
# cohortDiagnosticsDir : folder containing CohortDiagnostics exports
# outputFolder         : folder for diagnostic result CSV
# siteId               : site identifier from .env / SITE_ID
# cohortId             : cohort_definition_id for KLiNSIGHT (default 1)
# ============================================================

runKLiNSIGHTDiagnostics <- function(cohortDiagnosticsDir,
                                     outputFolder,
                                     siteId,
                                     cohortId = 1L) {

  checkDir <- file.path("R", "StudyDiagnostics", "KLiNSIGHT", "checks")
  for (f in sort(list.files(checkDir, pattern = "\\.R$", full.names = TRUE))) {
    source(f)
  }

  ParallelLogger::logInfo("=== KLiNSIGHT Study Diagnostics ===")

  checkDate <- as.character(Sys.Date())

  checks <- rbind(
    runKLiNSIGHTGenderPlausibility(
      cohortDiagnosticsDir = cohortDiagnosticsDir,
      siteId               = siteId,
      cohortId             = cohortId,
      checkDate            = checkDate
    ),
    runKLiNSIGHTCohortEntryYearPlausibility(
      cohortDiagnosticsDir = cohortDiagnosticsDir,
      siteId               = siteId,
      cohortId             = cohortId,
      checkDate            = checkDate
    ),
    runKLiNSIGHTAgeGroupPlausibility(
      cohortDiagnosticsDir = cohortDiagnosticsDir,
      siteId               = siteId,
      cohortId             = cohortId,
      checkDate            = checkDate
    ),
    runKLiNSIGHTIndexDiagnosisDistribution(
      cohortDiagnosticsDir = cohortDiagnosticsDir,
      siteId               = siteId,
      cohortId             = cohortId,
      checkDate            = checkDate
    ),
    runKLiNSIGHTLabAvailability(
      cohortDiagnosticsDir = cohortDiagnosticsDir,
      siteId               = siteId,
      cohortId             = cohortId,
      checkDate            = checkDate
    )
    # Further checks will be added here as they are built
  )

  outFile <- file.path(outputFolder, "INSiGHT_KLiNSIGHT_diagnostics.csv")
  write.csv(checks, outFile, row.names = FALSE)
  ParallelLogger::logInfo(sprintf("KLiNSIGHT diagnostics written to %s", outFile))

  invisible(checks)
}
