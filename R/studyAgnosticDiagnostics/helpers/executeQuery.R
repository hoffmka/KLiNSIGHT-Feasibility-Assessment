# Adapted from darwin-eu/CdmOnboarding (Apache 2.0)
# Simplified for use as a study package (no packageName — SQL path is explicit).

executeQuery <- function(
    sqlFilePath,
    connection,
    outputFolder,
    successMessage = NULL,
    useExecuteSql  = FALSE,
    ...
) {
  sql <- paste(readLines(sqlFilePath), collapse = "\n")
  sql <- do.call(
    SqlRender::render,
    c(sql = sql, warnOnMissingParameters = FALSE, list(...))
  )
  sql <- SqlRender::translate(sql, targetDialect = connection@dbms)

  result   <- NULL
  duration <- -1
  errorFile <- file.path(outputFolder,
                         paste0(tools::file_path_sans_ext(basename(sqlFilePath)), "Err.txt"))

  tryCatch({
    t0 <- Sys.time()

    if (useExecuteSql) {
      DatabaseConnector::executeSql(
        connection        = connection,
        sql               = sql,
        errorReportFile   = errorFile,
        reportOverallTime = FALSE
      )
    } else {
      result <- DatabaseConnector::querySql(
        connection      = connection,
        sql             = sql,
        errorReportFile = errorFile
      )
      names(result) <- toupper(names(result))   # DatabaseConnector v7 compatibility
    }

    duration <- as.numeric(difftime(Sys.time(), t0), units = "secs")
    msg <- successMessage %||% sprintf("'%s' executed successfully", basename(sqlFilePath))
    ParallelLogger::logInfo(sprintf("> %s in %.2f secs", msg, duration))
  },
  error = function(e) {
    ParallelLogger::logError(e)
    ParallelLogger::logError(sprintf("> Query failed. See '%s'", errorFile))
  })

  list(result = result, duration = duration)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b
