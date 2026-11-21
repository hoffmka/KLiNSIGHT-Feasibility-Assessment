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
# Usage
# -----
# Run interactively from the repository root after codeToRun.R
# has been executed (cohort tables must exist in COHORT_SCHEMA):
#
#   source(file.path("R", "explore_unmapped_measurements.R"))
#   unmapped <- getUnmappedMeasurements(cohortDefinitionId = 1L)
#   View(unmapped)
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
                                     minCount           = 1L,
                                     outputFile         = NULL) {

  # ---- Load .env and connect ----------------------------------------
  if (!requireNamespace("dotenv", quietly = TRUE)) {
    stop("Package 'dotenv' is required. Install with: install.packages('dotenv')")
  }
  dotenv::load_dot_env(".env")

  connectionDetails <- DatabaseConnector::createConnectionDetails(
    dbms         = Sys.getenv("DB_DBMS"),
    server       = Sys.getenv("DB_SERVER"),
    port         = as.integer(Sys.getenv("DB_PORT")),
    user         = Sys.getenv("DB_USER"),
    password     = Sys.getenv("DB_PASSWORD"),
    pathToDriver = Sys.getenv("DB_PRIVER")
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

  cdmSchema    <- Sys.getenv("CDM_SCHEMA")
  cohortSchema <- Sys.getenv("COHORT_SCHEMA")

  # ---- Query -----------------------------------------------------------
  # Returns one row per distinct (source_value, unit_source_value) pair.
  # n_persons   : number of distinct patients with this measurement source value
  # n_measurements : total number of measurement records
  # first_date / last_date : temporal range of the measurement in the cohort
  sql <- "
SELECT
  m.measurement_source_value,
  m.unit_source_value,
  COUNT(DISTINCT m.person_id)  AS n_persons,
  COUNT(*)                     AS n_measurements,
  MIN(m.measurement_date)      AS first_date,
  MAX(m.measurement_date)      AS last_date
FROM @cdm_schema.measurement m
INNER JOIN @cohort_schema.cohort c
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
    cohort_id            = cohortDefinitionId,
    min_count            = minCount,
    snakeCaseToCamelCase = FALSE
  )

  message(sprintf("Found %d distinct source value / unit combinations.", nrow(result)))

  # ---- Convenience: flag likely KS-relevant labs ----------------------
  ksPatterns <- c(
    "testoster" = "Testosterone",
    "fsh"       = "FSH",
    "follitrop" = "FSH",
    "lh\\b"     = "LH",
    "lutrop"    = "LH",
    "lutroph"   = "LH",
    "tsh"       = "TSH",
    "thyrotropin" = "TSH",
    "amh"       = "AMH",
    "inhibin"   = "Inhibin",
    "estradiol" = "Estradiol",
    "prolactin" = "Prolactin"
  )

  result$ks_relevant_lab <- NA_character_
  for (pat in names(ksPatterns)) {
    hits <- grepl(pat, result$measurement_source_value, ignore.case = TRUE)
    result$ks_relevant_lab[hits & is.na(result$ks_relevant_lab)] <- ksPatterns[[pat]]
  }

  # ---- Output ----------------------------------------------------------
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
# View(unmapped)
#
# KS-relevante Werte filtern:
# unmapped[!is.na(unmapped$ks_relevant_lab), ]
