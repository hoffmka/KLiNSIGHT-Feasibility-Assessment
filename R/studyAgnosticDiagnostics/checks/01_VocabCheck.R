runVocabCheck <- function(connection, cdmDatabaseSchema, outputFolder, siteId) {

  sqlDir <- file.path("sql", "sql_server")

  ParallelLogger::logInfo("Running vocabulary check...")

  vocabCounts <- executeQuery(
    sqlFilePath       = file.path(sqlDir, "vocab_versions.sql"),
    connection        = connection,
    outputFolder      = outputFolder,
    successMessage    = "Vocabulary counts",
    cdmDatabaseSchema = cdmDatabaseSchema
  )

  result    <- vocabCounts$result
  checkDate <- as.character(Sys.Date())

  # --- Row 1: vocabulary bundle version ---
  bundleVersion <- result[result$ID == "None", "VERSION"]
  if (length(bundleVersion) == 0 || is.na(bundleVersion)) {
    bundleVersion <- "UNKNOWN"
    versionStatus <- "WARNING"
    versionMsg    <- "OMOP vocabulary bundle version not found in VOCABULARY table"
  } else {
    versionStatus <- "PASS"
    versionMsg    <- "OMOP vocabulary bundle version"
  }
  ParallelLogger::logInfo(sprintf("  Vocabulary bundle version: %s", bundleVersion))

  # --- Row 2: ORPHA vocabulary presence ---
  orphaRow <- result[result$ID == "ORPHA", ]
  if (nrow(orphaRow) == 0) {
    orphaPresent <- FALSE
    orphaValue   <- "FALSE"
    orphaStatus  <- "WARNING"
    orphaMsg     <- "ORPHA vocabulary absent"
    ParallelLogger::logWarn("  ORPHA vocabulary NOT found.")
  } else {
    orphaPresent <- TRUE
    orphaValue   <- as.character(orphaRow$N_STANDARD_CONCEPTS)
    orphaStatus  <- "PASS"
    orphaMsg     <- sprintf("ORPHA vocabulary present (version: %s)", orphaRow$VERSION)
    ParallelLogger::logInfo(sprintf(
      "  ORPHA vocabulary found (version: %s, standard concepts: %s)",
      orphaRow$VERSION, orphaRow$N_STANDARD_CONCEPTS
    ))
  }

  checks <- data.frame(
    SITE_ID     = siteId,
    CHECK_DATE  = checkDate,
    CHECK_NAME  = c("VOCABULARY_BUNDLE_VERSION", "ORPHA_VOCABULARY_PRESENT"),
    CHECK_LEVEL = "METADATA",
    STATUS      = c(versionStatus, orphaStatus),
    VALUE       = c(bundleVersion, orphaValue),
    MESSAGE     = c(versionMsg, orphaMsg),
    stringsAsFactors = FALSE
  )

  invisible(list(orphaPresent = orphaPresent, checks = checks))
}
