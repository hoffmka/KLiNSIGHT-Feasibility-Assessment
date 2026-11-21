# ============================================================
# Explore unmapped measurements (concept_id = 0) for a cohort
# ============================================================
#
# Queries the OMOP CDM measurement table for all entries where
# measurement_concept_id = 0 (source-coded, not mapped to a
# standard OMOP concept) for patients in a specified cohort.
#
# Use this script to investigate potential data gaps flagged by
# the StudyDiagnostics lab availability check (05_LabAvailability.R).
# If key labs (Testosterone, FSH, LH, TSH) are absent from the
# CohortDiagnostics temporal characterization, they may still
# exist in the measurement table under source codes only.
#
# A result of 0 rows means all measurement records for this cohort
# already carry a standard OMOP concept (measurement_concept_id > 0)
# — which is the best possible outcome.
#
# Usage
# -----
# Run interactively from the repository root after codeToRun.R
# has been executed (cohort tables must exist in COHORT_SCHEMA):
#
#   source(file.path("R", "explore_unmapped_measurements.R"))
#   unmapped <- getUnmappedMeasurements(cohortDefinitionId = 1L)
#
# Parameters
# ----------
# cohortDefinitionId : cohort_definition_id to restrict to
#                      (1 = KLiNSIGHT basic cohort, default)
# minCount           : suppress rows with n_persons < minCount
#                      (set to 5 for privacy-compliant output;
#                       set to 1 for internal exploration)
# outputFile         : optional path; if set, results are written
#                      as CSV
# ============================================================

getUnmappedMeasurements <- function(cohortDefinitionId = 1L,
                                     cohortTable        = NULL,
                                     minCount           = 1L,
                                     outputFile         = NULL) {

  # ---- Load .env and connect ----------------------------------------
  if (!requireNamespace("dotenv", quietly = TRUE)) {
    stop("Package 'dotenv' is required. Install with: install.packages('dotenv')")
  }
  dotenv::load_dot_env(".env")

  if (is.null(cohortTable)) {
    cohortTable <- Sys.getenv("COHORT_TABLE", unset = "insight_cohort")
  }

  connectionDetails <- DatabaseConnector::createConnectionDetails(
    dbms         = Sys.getenv("DB_DBMS"),
    server       = Sys.getenv("DB_SERVER"),
    port         = as.integer(Sys.getenv("DB_PORT")),
    user         = Sys.getenv("DB_USER"),
    password     = Sys.getenv("DB_PASSWORD"),
    pathToDriver = Sys.getenv("DB_PATHTODRIVER")
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

  # ---- Sanity check: how many measurements exist for this cohort? ----
  sqlTotal <- "
SELECT COUNT(*) AS n_total
FROM @cdm_schema.measurement m
INNER JOIN @cohort_schema.@cohort_table c
  ON  m.person_id            = c.subject_id
  AND c.cohort_definition_id = @cohort_id
"
  total <- DatabaseConnector::renderTranslateQuerySql(
    connection           = connection,
    sql                  = sqlTotal,
    cdm_schema           = cdmSchema,
    cohort_schema        = cohortSchema,
    cohort_table         = cohortTable,
    cohort_id            = cohortDefinitionId,
    snakeCaseToCamelCase = FALSE
  )
  message(sprintf("Total measurement records for cohort %d: %s",
                  cohortDefinitionId, format(total$n_total, big.mark = ",")))

  # ---- Main query: unmapped only -------------------------------------
  sql <- "
SELECT
  m.measurement_source_value,
  m.unit_source_value,
  COUNT(DISTINCT m.person_id)  AS n_persons,
  COUNT(*)                     AS n_measurements,
  MIN(m.measurement_date)      AS first_date,
  MAX(m.measurement_date)      AS last_date
FROM @cdm_schema.measurement m
INNER JOIN @cohort_schema.@cohort_table c
  ON  m.person_id            = c.subject_id
  AND c.cohort_definition_id = @cohort_id
WHERE m.measurement_concept_id = 0
GROUP BY
  m.measurement_source_value,
  m.unit_source_value
HAVING COUNT(DISTINCT m.person_id) >= @min_count
ORDER BY n_persons DESC, n_measurements DESC
"

  message(sprintf(
    "Querying unmapped measurements for cohort_definition_id = %d (min persons: %d)...",
    cohortDefinitionId, minCount
  ))

  result <- DatabaseConnector::renderTranslateQuerySql(
    connection           = connection,
    sql                  = sql,
    cdm_schema           = cdmSchema,
    cohort_schema        = cohortSchema,
    cohort_table         = cohortTable,
    cohort_id            = cohortDefinitionId,
    min_count            = minCount,
    snakeCaseToCamelCase = FALSE
  )

  if (nrow(result) == 0) {
    message(sprintf(
      paste0("No unmapped measurements found (measurement_concept_id = 0) for cohort %d.\n",
             "  All %s measurement records carry a standard OMOP concept — no ETL gap detected."),
      cohortDefinitionId,
      format(total$n_total, big.mark = ",")
    ))
    return(invisible(result))
  }

  message(sprintf("Found %d distinct source value / unit combinations.", nrow(result)))

  # ---- Flag KS-relevant source patterns ------------------------------
  ksPatterns <- c(
    "testoster"  = "Testosterone",
    "fsh"        = "FSH",
    "follitrop"  = "FSH",
    "\\blh\\b"   = "LH",
    "lutrop"     = "LH",
    "\\btsh\\b"  = "TSH",
    "thyrotropin"= "TSH",
    "amh"        = "AMH",
    "inhibin"    = "Inhibin",
    "estradiol"  = "Estradiol",
    "prolactin"  = "Prolactin"
  )

  result$ks_relevant_lab <- NA_character_
  for (pat in names(ksPatterns)) {
    hits <- grepl(pat, result$measurement_source_value, ignore.case = TRUE)
    result$ks_relevant_lab[hits & is.na(result$ks_relevant_lab)] <- ksPatterns[[pat]]
  }

  # ---- Output --------------------------------------------------------
  if (!is.null(outputFile)) {
    dir.create(dirname(outputFile), recursive = TRUE, showWarnings = FALSE)
    write.csv(result, outputFile, row.names = FALSE)
    message(sprintf("Results written to %s", outputFile))
  }

  invisible(result)
}

# ---- Interactive convenience call ------------------------------------
# Uncomment and run directly if sourcing this file:
#
# unmapped <- getUnmappedMeasurements(
#   cohortDefinitionId = 1L,
#   minCount           = 1L,
#   outputFile         = file.path("output", "klinsight_unmapped_measurements.csv")
# )
#
# KS-relevante Werte filtern:
# unmapped[!is.na(unmapped$ks_relevant_lab), ]
