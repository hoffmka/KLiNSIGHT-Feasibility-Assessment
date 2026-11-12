
# ============================================================
# Cohort characterization
# 2. Cohort entry year
# ============================================================
#
# Characterizes the temporal distribution of cohort entries.
#
# Each subject is counted only once per cohort, using the
# earliest cohort_start_date.
#
# ============================================================


# ------------------------------------------------------------
# 1. Retrieve first cohort entry per subject
# ------------------------------------------------------------

schemaSql <- as.character(
  DBI::dbQuoteIdentifier(
    conn,
    cohortDatabaseSchema
  )
)

tableSql <- as.character(
  DBI::dbQuoteIdentifier(
    conn,
    cohortTable
  )
)

query <- paste0(
  "SELECT ",
  "cohort_definition_id AS cohort_id, ",
  "subject_id AS subject_id, ",
  "MIN(cohort_start_date) AS first_cohort_start_date ",
  "FROM ",
  schemaSql,
  ".",
  tableSql,
  " GROUP BY ",
  "cohort_definition_id, subject_id"
)

cohortEntries <- DBI::dbGetQuery(
  conn,
  query
)


# ------------------------------------------------------------
# 2. Determine cohort entry year
# ------------------------------------------------------------

cohortEntryResults <- cohortEntries |>
  dplyr::mutate(
    cohortId = as.integer(cohort_id),
    firstCohortStartDate = as.Date(
      first_cohort_start_date
    ),
    entryYear = as.integer(
      format(firstCohortStartDate, "%Y")
    )
  ) |>
  dplyr::left_join(
    cohortSettings,
    by = "cohortId"
  ) |>
  dplyr::count(
    cohortId,
    cohortName,
    entryYear,
    name = "count"
  ) |>
  dplyr::group_by(cohortId) |>
  dplyr::mutate(
    percentage = count / sum(count) * 100
  ) |>
  dplyr::ungroup() |>
  dplyr::select(
    cohortId,
    cohortName,
    entryYear,
    count,
    percentage
  ) |>
  dplyr::arrange(
    cohortId,
    entryYear
  )


# ------------------------------------------------------------
# 3. Export results
# ------------------------------------------------------------

outputFile <- file.path(
  characterizationDir,
  paste0(
    "cohort_entry_year_",
    Sys.Date(),
    ".csv"
  )
)

write.csv(
  cohortEntryResults,
  outputFile,
  row.names = FALSE,
  na = ""
)

message("\nCohort entry year characterization completed.")
message("Results saved to: ", outputFile)

print(cohortEntryResults)
