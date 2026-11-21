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
#   source(file.path("R", "explore_unmapped_source_codes.R"))
#
#   # Single cohort
#   meas <- getUnmappedMeasurements(cohortDefinitionId = 1L, minCount = 5L)
#   drug <- getUnmappedDrugExposures(cohortDefinitionId = 1L, minCount = 5L)
#
#   # All cohorts defined in cohortsToCreate/Cohorts.csv
#   meas <- getUnmappedMeasurements(minCount = 5L)
#   drug <- getUnmappedDrugExposures(minCount = 5L)
#
# Parameters (shared by both functions)
# --------------------------------------
#   cohortDefinitionId : integer or integer vector of cohort IDs, or NULL
#                        (NULL = all cohorts from cohortsToCreate/Cohorts.csv)
#   cohortTable        : cohort table name; default: env COHORT_TABLE or
#                        "insight_cohort"
#   minCount           : suppress rows with n_persons < minCount
#                        default: 5 (privacy-compliant);
#                        use 1 only for internal exploration
#   outputFile         : optional CSV path; output includes cohort_id /
#                        cohort_name columns when multiple cohorts are queried
# ============================================================

# ---- Shared helpers --------------------------------------------------

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

# Returns a named character vector: names = cohortId (as character),
# values = cohortName.  Reads cohortsToCreate/Cohorts.csv.
.loadCohortRegistry <- function() {
  csvPath <- file.path("cohortsToCreate", "Cohorts.csv")
  if (!file.exists(csvPath))
    stop("cohortsToCreate/Cohorts.csv not found — run from repository root")
  reg <- read.csv(csvPath, stringsAsFactors = FALSE)
  stats::setNames(reg$cohortName, as.character(reg$cohortId))
}

# Resolve cohortDefinitionId:
#   NULL           -> all IDs from Cohorts.csv
#   integer/vector -> as supplied, with names from registry (or fallback)
.resolveCohortIds <- function(cohortDefinitionId) {
  reg <- .loadCohortRegistry()
  if (is.null(cohortDefinitionId)) {
    return(list(ids = as.integer(names(reg)), names = unname(reg)))
  }
  ids <- as.integer(cohortDefinitionId)
  nms <- sapply(ids, function(i) {
    n <- reg[as.character(i)]
    if (length(n) == 0 || is.na(n)) paste0("cohort_", i) else n
  })
  list(ids = ids, names = nms)
}

# ================================================================
# getUnmappedMeasurements
# ================================================================
getUnmappedMeasurements <- function(cohortDefinitionId = NULL,
                                     cohortTable        = NULL,
                                     minCount           = 5L,
                                     outputFile         = NULL) {
  # cohortDefinitionId: single integer, integer vector, or NULL (= all cohorts)
  cohortIds   <- .resolveCohortIds(cohortDefinitionId)
  cohortTable <- .defaultCohortTable(cohortTable)
  connection  <- .connectFromEnv()
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

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

  allResults <- lapply(seq_along(cohortIds$ids), function(i) {
    cohortId   <- cohortIds$ids[i]
    cohortName <- cohortIds$names[i]

    # Sanity check: total measurement records for this cohort
    total <- DatabaseConnector::renderTranslateQuerySql(connection,
      "SELECT COUNT(*) AS n FROM @cdm_schema.measurement m
       INNER JOIN @cohort_schema.@cohort_table c
         ON m.person_id = c.subject_id AND c.cohort_definition_id = @cohort_id",
      cdm_schema = cdmSchema, cohort_schema = cohortSchema,
      cohort_table = cohortTable, cohort_id = cohortId,
      snakeCaseToCamelCase = FALSE)
    message(sprintf("[%s] Total measurement records: %s",
                    cohortName, format(total$n, big.mark = ",")))

    if (total$n == 0) {
      message(sprintf("  Skipping cohort %d — no measurement records.", cohortId))
      return(NULL)
    }

    message(sprintf("  Querying unmapped measurements (min persons: %d)...", minCount))

    result <- DatabaseConnector::renderTranslateQuerySql(connection, sql,
      cdm_schema = cdmSchema, cohort_schema = cohortSchema,
      cohort_table = cohortTable, cohort_id = cohortId,
      min_count = minCount, snakeCaseToCamelCase = FALSE)

    if (nrow(result) == 0) {
      message(sprintf(
        "  No unmapped measurements found.\n  All %s records carry a standard OMOP concept.",
        format(total$n, big.mark = ",")))
      return(NULL)
    }

    message(sprintf("  Found %d distinct unmapped source value(s).", nrow(result)))
    result$cohort_id   <- cohortId
    result$cohort_name <- cohortName
    result
  })

  combined <- do.call(rbind, Filter(Negate(is.null), allResults))
  if (is.null(combined)) {
    message("No unmapped measurements found across all queried cohorts.")
    combined <- data.frame()
  }

  if (!is.null(outputFile) && nrow(combined) > 0) {
    dir.create(dirname(outputFile), recursive = TRUE, showWarnings = FALSE)
    write.csv(combined, outputFile, row.names = FALSE)
    message(sprintf("Written to %s", outputFile))
  }

  invisible(combined)
}

# ================================================================
# getUnmappedDrugExposures
# ================================================================
getUnmappedDrugExposures <- function(cohortDefinitionId = NULL,
                                      cohortTable        = NULL,
                                      minCount           = 5L,
                                      outputFile         = NULL) {
  # cohortDefinitionId: single integer, integer vector, or NULL (= all cohorts)
  cohortIds   <- .resolveCohortIds(cohortDefinitionId)
  cohortTable <- .defaultCohortTable(cohortTable)
  connection  <- .connectFromEnv()
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

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
-- Try to resolve source_value as an RxNorm or ATC code
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

  allResults <- lapply(seq_along(cohortIds$ids), function(i) {
    cohortId   <- cohortIds$ids[i]
    cohortName <- cohortIds$names[i]

    total <- DatabaseConnector::renderTranslateQuerySql(connection,
      "SELECT COUNT(*) AS n FROM @cdm_schema.drug_exposure de
       INNER JOIN @cohort_schema.@cohort_table c
         ON de.person_id = c.subject_id AND c.cohort_definition_id = @cohort_id",
      cdm_schema = cdmSchema, cohort_schema = cohortSchema,
      cohort_table = cohortTable, cohort_id = cohortId,
      snakeCaseToCamelCase = FALSE)
    message(sprintf("[%s] Total drug_exposure records: %s",
                    cohortName, format(total$n, big.mark = ",")))

    if (total$n == 0) {
      message(sprintf("  Skipping cohort %d — no drug_exposure records.", cohortId))
      return(NULL)
    }

    message(sprintf("  Querying unmapped drug exposures (min persons: %d)...", minCount))

    result <- DatabaseConnector::renderTranslateQuerySql(connection, sql,
      cdm_schema = cdmSchema, cohort_schema = cohortSchema,
      cohort_table = cohortTable, cohort_id = cohortId,
      min_count = minCount, snakeCaseToCamelCase = FALSE)

    if (nrow(result) == 0) {
      message(sprintf(
        "  No unmapped drug exposures found.\n  All %s records carry a standard OMOP concept.",
        format(total$n, big.mark = ",")))
      return(NULL)
    }

    message(sprintf("  Found %d distinct unmapped drug source value(s).", nrow(result)))
    result$cohort_id   <- cohortId
    result$cohort_name <- cohortName
    result
  })

  combined <- do.call(rbind, Filter(Negate(is.null), allResults))
  if (is.null(combined)) {
    message("No unmapped drug exposures found across all queried cohorts.")
    combined <- data.frame()
  }

  if (!is.null(outputFile) && nrow(combined) > 0) {
    dir.create(dirname(outputFile), recursive = TRUE, showWarnings = FALSE)
    write.csv(combined, outputFile, row.names = FALSE)
    message(sprintf("Written to %s", outputFile))
  }

  invisible(combined)
}

# ================================================================
# Example usage
# ================================================================
# source(file.path("R", "explore_unmapped_source_codes.R"))
#
# # All cohorts defined in cohortsToCreate/Cohorts.csv:
# meas <- getUnmappedMeasurements(minCount = 5L)
# drug <- getUnmappedDrugExposures(minCount = 5L)
#
# # Single cohort, write to CSV:
# meas <- getUnmappedMeasurements(cohortDefinitionId = 1L, minCount = 5L,
#           outputFile = file.path("output", "klinsight_unmapped_measurements.csv"))
# drug <- getUnmappedDrugExposures(cohortDefinitionId = 1L, minCount = 5L,
#           outputFile = file.path("output", "klinsight_unmapped_drugs.csv"))
