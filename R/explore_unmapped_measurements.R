# ============================================================
# Explore unmapped source codes for a cohort
# ============================================================
#
# Two functions:
#
#   getUnmappedMeasurements()   — measurement table, concept_id = 0
#   getUnmappedDrugExposures()  — drug_exposure table, concept_id = 0
#
# Both include a vocabulary lookup: if the source_value matches a
# known standard code (LOINC for measurements; RxNorm / ATC for
# drugs), the concept_name and a resolvable concept_id are added
# automatically — making it easy to identify what is unmapped
# and to file an ETL mapping request.
#
# A result of 0 rows means all records for this cohort carry a
# standard OMOP concept — the best possible outcome.
#
# Usage (from repository root, after codeToRun.R has run):
# ----------------------------------------------------------
#   source(file.path("R", "explore_unmapped_measurements.R"))
#
#   meas <- getUnmappedMeasurements(cohortDefinitionId = 1L, minCount = 1L)
#   drug <- getUnmappedDrugExposures(cohortDefinitionId = 1L, minCount = 1L)
#
# Parameters (shared by both functions)
# --------------------------------------
#   cohortDefinitionId : cohort_definition_id (1 = KLiNSIGHT basic cohort)
#   cohortTable        : cohort table name; default: "insight_cohort"
#                        (overridden by COHORT_TABLE in .env if set)
#   minCount           : suppress rows with n_persons < minCount
#                        (use 5 for privacy-compliant output;
#                         use 1 for internal exploration)
#   outputFile         : optional CSV path
# ============================================================

# ---- Shared helper: connect from .env ----------------------------
.connectFromEnv <- function() {
  if (!requireNamespace("dotenv", quietly = TRUE))
    stop("Package 'dotenv' required. Install with: install.packages('dotenv')")
  dotenv::load_dot_env(".env")
  DatabaseConnector::connect(
    DatabaseConnector::createConnectionDetails(
      dbms         = Sys.getenv("DB_DBMS"),
      server       = Sys.getenv("DB_SERVER"),
      port         = as.integer(Sys.getenv("DB_PORT")),
      user         = Sys.getenv("DB_USER"),
      password     = Sys.getenv("DB_PASSWORD"),
      pathToDriver = Sys.getenv("DB_PATHTODRIVER")
    )
  )
}

.defaultCohortTable <- function(cohortTable) {
  if (is.null(cohortTable))
    Sys.getenv("COHORT_TABLE", unset = "insight_cohort")
  else
    cohortTable
}

# ================================================================
# getUnmappedMeasurements
# ================================================================
getUnmappedMeasurements <- function(cohortDefinitionId = 1L,
                                     cohortTable        = NULL,
                                     minCount           = 1L,
                                     outputFile         = NULL) {

  cohortTable  <- .defaultCohortTable(cohortTable)
  connection   <- .connectFromEnv()
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

  # Sanity check
  total <- DatabaseConnector::renderTranslateQuerySql(connection,
    "SELECT COUNT(*) AS n FROM @cdm_schema.measurement m
     INNER JOIN @cohort_schema.@cohort_table c
       ON m.person_id = c.subject_id AND c.cohort_definition_id = @cohort_id",
    cdm_schema = cdmSchema, cohort_schema = cohortSchema,
    cohort_table = cohortTable, cohort_id = cohortDefinitionId,
    snakeCaseToCamelCase = FALSE)
  message(sprintf("Total measurement records for cohort %d: %s",
                  cohortDefinitionId, format(total$n, big.mark = ",")))

  sql <- "
SELECT
  m.measurement_source_value                AS source_value,
  m.unit_source_value,
  cv.concept_id                             AS mapped_concept_id,
  cv.concept_name                           AS mapped_concept_name,
  COUNT(DISTINCT m.person_id)               AS n_persons,
  COUNT(*)                                  AS n_measurements,
  MIN(m.measurement_date)                   AS first_date,
  MAX(m.measurement_date)                   AS last_date
FROM @cdm_schema.measurement m
INNER JOIN @cohort_schema.@cohort_table c
  ON  m.person_id            = c.subject_id
  AND c.cohort_definition_id = @cohort_id
-- Try to resolve source_value as a LOINC code
LEFT JOIN @cdm_schema.concept cv
  ON  cv.concept_code      = m.measurement_source_value
  AND cv.vocabulary_id     = 'LOINC'
  AND cv.standard_concept  = 'S'
WHERE m.measurement_concept_id = 0
GROUP BY
  m.measurement_source_value,
  m.unit_source_value,
  cv.concept_id,
  cv.concept_name
HAVING COUNT(DISTINCT m.person_id) >= @min_count
ORDER BY n_persons DESC, n_measurements DESC
"

  message(sprintf("Querying unmapped measurements (cohort %d, min persons: %d)...",
                  cohortDefinitionId, minCount))

  result <- DatabaseConnector::renderTranslateQuerySql(connection, sql,
    cdm_schema = cdmSchema, cohort_schema = cohortSchema,
    cohort_table = cohortTable, cohort_id = cohortDefinitionId,
    min_count = minCount, snakeCaseToCamelCase = FALSE)

  if (nrow(result) == 0) {
    message(sprintf(
      "No unmapped measurements found for cohort %d.\n  All %s records carry a standard OMOP concept.",
      cohortDefinitionId, format(total$n, big.mark = ",")))
    return(invisible(result))
  }

  message(sprintf("Found %d distinct unmapped source value(s).", nrow(result)))

  if (!is.null(outputFile)) {
    dir.create(dirname(outputFile), recursive = TRUE, showWarnings = FALSE)
    write.csv(result, outputFile, row.names = FALSE)
    message(sprintf("Written to %s", outputFile))
  }
  invisible(result)
}

# ================================================================
# getUnmappedDrugExposures
# ================================================================
getUnmappedDrugExposures <- function(cohortDefinitionId = 1L,
                                      cohortTable        = NULL,
                                      minCount           = 1L,
                                      outputFile         = NULL) {

  cohortTable  <- .defaultCohortTable(cohortTable)
  connection   <- .connectFromEnv()
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

  # Sanity check
  total <- DatabaseConnector::renderTranslateQuerySql(connection,
    "SELECT COUNT(*) AS n FROM @cdm_schema.drug_exposure de
     INNER JOIN @cohort_schema.@cohort_table c
       ON de.person_id = c.subject_id AND c.cohort_definition_id = @cohort_id",
    cdm_schema = cdmSchema, cohort_schema = cohortSchema,
    cohort_table = cohortTable, cohort_id = cohortDefinitionId,
    snakeCaseToCamelCase = FALSE)
  message(sprintf("Total drug_exposure records for cohort %d: %s",
                  cohortDefinitionId, format(total$n, big.mark = ",")))

  sql <- "
SELECT
  de.drug_source_value                      AS source_value,
  cv.concept_id                             AS mapped_concept_id,
  cv.concept_name                           AS mapped_concept_name,
  cv.vocabulary_id                          AS matched_vocabulary,
  COUNT(DISTINCT de.person_id)              AS n_persons,
  COUNT(*)                                  AS n_exposures,
  MIN(de.drug_exposure_start_date)          AS first_date,
  MAX(de.drug_exposure_start_date)          AS last_date
FROM @cdm_schema.drug_exposure de
INNER JOIN @cohort_schema.@cohort_table c
  ON  de.person_id           = c.subject_id
  AND c.cohort_definition_id = @cohort_id
-- Try to resolve source_value as RxNorm or ATC code
LEFT JOIN @cdm_schema.concept cv
  ON  cv.concept_code     = de.drug_source_value
  AND cv.vocabulary_id    IN ('RxNorm', 'RxNorm Extension', 'ATC')
  AND cv.standard_concept = 'S'
WHERE de.drug_concept_id = 0
GROUP BY
  de.drug_source_value,
  cv.concept_id,
  cv.concept_name,
  cv.vocabulary_id
HAVING COUNT(DISTINCT de.person_id) >= @min_count
ORDER BY n_persons DESC, n_exposures DESC
"

  message(sprintf("Querying unmapped drug exposures (cohort %d, min persons: %d)...",
                  cohortDefinitionId, minCount))

  result <- DatabaseConnector::renderTranslateQuerySql(connection, sql,
    cdm_schema = cdmSchema, cohort_schema = cohortSchema,
    cohort_table = cohortTable, cohort_id = cohortDefinitionId,
    min_count = minCount, snakeCaseToCamelCase = FALSE)

  if (nrow(result) == 0) {
    message(sprintf(
      "No unmapped drug exposures found for cohort %d.\n  All %s records carry a standard OMOP concept.",
      cohortDefinitionId, format(total$n, big.mark = ",")))
    return(invisible(result))
  }

  message(sprintf("Found %d distinct unmapped drug source value(s).", nrow(result)))

  if (!is.null(outputFile)) {
    dir.create(dirname(outputFile), recursive = TRUE, showWarnings = FALSE)
    write.csv(result, outputFile, row.names = FALSE)
    message(sprintf("Written to %s", outputFile))
  }
  invisible(result)
}

# ================================================================
# Convenience: run both at once
# ================================================================
# source(file.path("R", "explore_unmapped_measurements.R"))
#
# meas <- getUnmappedMeasurements(cohortDefinitionId = 1L, minCount = 1L,
#           outputFile = file.path("output", "klinsight_unmapped_measurements.csv"))
#
# drug <- getUnmappedDrugExposures(cohortDefinitionId = 1L, minCount = 1L,
#           outputFile = file.path("output", "klinsight_unmapped_drugs.csv"))
