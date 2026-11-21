# ============================================================
# CohortDiagnostics — standalone runner
# ============================================================
#
# Wraps CohortDiagnostics::executeDiagnostics() with the
# INSiGHT-specific set of enabled modules (index event
# breakdown only).  Called directly from codeToRun.R after
# cohort creation.
#
# Parameters
# ----------
# cohortDefinitionSet  : from CohortGenerator::getCohortDefinitionSet()
# connectionDetails    : DatabaseConnector connection details
# cdmDatabaseSchema    : CDM schema
# cohortDatabaseSchema : cohort table schema
# cohortTable          : cohort table name
# cohortDiagnosticsDir : export folder for all CohortDiagnostics output
# siteId               : site identifier from .env / SITE_ID
# privacyThreshold     : small-cell suppression threshold (default 5)
#
# Output
# ------
#   <cohortDiagnosticsDir>/
#     index_event_breakdown.csv
#     concept.csv
#     visit_context.csv
#     metadata.csv
#     vocabulary.csv
#     … (full CohortDiagnostics export)
# ============================================================

runCohortDiagnostics <- function(cohortDefinitionSet,
                                  connectionDetails,
                                  cdmDatabaseSchema,
                                  cohortDatabaseSchema,
                                  cohortTable,
                                  cohortDiagnosticsDir,
                                  siteId,
                                  privacyThreshold = 5L) {

  dir.create(cohortDiagnosticsDir, recursive = TRUE, showWarnings = FALSE)

  message("\nRunning: CohortDiagnostics (index event breakdown)")

  CohortDiagnostics::executeDiagnostics(
    cohortDefinitionSet               = cohortDefinitionSet,
    connectionDetails                 = connectionDetails,
    cdmDatabaseSchema                 = cdmDatabaseSchema,
    cohortDatabaseSchema              = cohortDatabaseSchema,
    cohortTable                       = cohortTable,
    exportFolder                      = cohortDiagnosticsDir,
    databaseId                        = siteId,
    runBreakdownIndexEvents           = TRUE,
    runInclusionStatistics            = FALSE,
    runTemporalCohortCharacterization = FALSE,
    runIncidenceRate                  = FALSE,
    runOrphanConcepts                 = FALSE,
    minCellCount                      = privacyThreshold
  )

  message("CohortDiagnostics completed.")
  message("Results saved to: ", cohortDiagnosticsDir)

  invisible(cohortDiagnosticsDir)
}
