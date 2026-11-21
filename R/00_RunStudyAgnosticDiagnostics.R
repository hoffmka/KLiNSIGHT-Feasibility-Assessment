# Level 1 diagnostics — study-agnostic CDM and vocabulary metadata checks.
#
# Usage (from repo root):
#   source(file.path("R", "00_RunStudyAgnosticDiagnostics.R"))
#   level1Results <- runStudyAgnosticDiagnostics(connection, cdmDatabaseSchema, outputFolder, siteId)
#
# To add a new check: drop a new .R file into studyAgnosticDiagnostics/R/checks/.
# It will be sourced automatically and its result must be a list(checks = <data.frame>).

runStudyAgnosticDiagnostics <- function(connection, cdmDatabaseSchema, outputFolder, siteId) {

  rootDir <- file.path("R", "studyAgnosticDiagnostics")

  # Source helpers
  for (f in sort(list.files(file.path(rootDir, "helpers"), full.names = TRUE, pattern = "\\.R$"))) {
    source(f)
  }

  # Source checks
  for (f in sort(list.files(file.path(rootDir, "checks"), full.names = TRUE, pattern = "\\.R$"))) {
    source(f)
  }

  ParallelLogger::logInfo("=== Level 1 Diagnostics ===")

  cdmResults   <- runCdmSourceCheck(connection, cdmDatabaseSchema, outputFolder, siteId)
  vocabResults <- runVocabCheck(connection, cdmDatabaseSchema, outputFolder, siteId)

  allChecks <- rbind(cdmResults$checks, vocabResults$checks)

  outFile <- file.path(outputFolder, "INSiGHT_studyAgnostic_diagnostics.csv")
  write.csv(allChecks, outFile, row.names = FALSE)
  ParallelLogger::logInfo(sprintf("Level 1 diagnostics written to %s", outFile))

  invisible(list(
    cdmVersion   = cdmResults$cdmVersion,
    orphaPresent = vocabResults$orphaPresent,
    checks       = allChecks
  ))
}
