runCdmSourceCheck <- function(connection, cdmDatabaseSchema, outputFolder, siteId) {


  ParallelLogger::logInfo("Running CDM source check...")

  sqlDir <- file.path("sql", "sql_server")

  cdmSource <- executeQuery(
    sqlFilePath       = file.path(sqlDir, "cdm_source.sql"),
    connection        = connection,
    outputFolder      = outputFolder,
    successMessage    = "CDM source metadata",
    cdmDatabaseSchema = cdmDatabaseSchema
  )

  result    <- cdmSource$result
  checkDate <- as.character(Sys.Date())

  if (is.null(result) || nrow(result) == 0) {
    ParallelLogger::logWarn("  CDM_SOURCE table is empty or not accessible.")
    checks <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = "CDM_VERSION",
      CHECK_LEVEL = "METADATA",
      STATUS      = "WARNING",
      VALUE       = "UNKNOWN",
      MESSAGE     = "CDM_SOURCE table empty or not accessible",
      stringsAsFactors = FALSE
    )
  } else {
    row <- result[1, ]
    cdmVersion <- as.character(row$CDM_VERSION)
    ParallelLogger::logInfo(sprintf("  CDM version: %s", cdmVersion))
    ParallelLogger::logInfo(sprintf("  CDM source:  %s", row$CDM_SOURCE_NAME))
    ParallelLogger::logInfo(sprintf("  CDM release: %s", row$CDM_RELEASE_DATE))

    checks <- data.frame(
      SITE_ID     = siteId,
      CHECK_DATE  = checkDate,
      CHECK_NAME  = c("CDM_VERSION", "CDM_SOURCE_NAME", "CDM_RELEASE_DATE"),
      CHECK_LEVEL = "METADATA",
      STATUS      = "PASS",
      VALUE       = c(
        cdmVersion,
        as.character(row$CDM_SOURCE_NAME),
        as.character(row$CDM_RELEASE_DATE)
      ),
      MESSAGE     = c(
        "OMOP CDM version",
        "CDM source / ETL name",
        "Date of last CDM release at this site"
      ),
      stringsAsFactors = FALSE
    )
  }

  invisible(list(cdmVersion = checks$VALUE[checks$CHECK_NAME == "CDM_VERSION"], checks = checks))
}
