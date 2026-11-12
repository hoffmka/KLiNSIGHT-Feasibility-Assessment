
# ============================================================
# Cohort counts
# ============================================================
#
# Retrieves the number of cohort entries and unique subjects
# for each generated cohort.
#
# ============================================================


# ------------------------------------------------------------
# 1. Retrieve cohort counts
# ------------------------------------------------------------

results <- CohortGenerator::getCohortCounts(
  connection = conn,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable = cohortTable
)


# ------------------------------------------------------------
# 2. Include cohorts with zero subjects
# ------------------------------------------------------------

allCohorts <- cohortDefinitionSet |>
  dplyr::select(
    cohortId,
    cohortName
  )

results <- allCohorts |>
  dplyr::left_join(
    results,
    by = "cohortId"
  )

# Replace missing counts with zero
results <- results |>
  dplyr::mutate(
    cohortEntries = dplyr::coalesce(cohortEntries, 0L),
    cohortSubjects = dplyr::coalesce(cohortSubjects, 0L)
  )


# ------------------------------------------------------------
# 3. Apply privacy-preserving display
# ------------------------------------------------------------

if (suppressSmallCounts) {
  
  formatCount <- function(x) {
    ifelse(
      x == 0,
      "0",
      ifelse(
        x < privacyThreshold,
        paste0("<", privacyThreshold),
        as.character(x)
      )
    )
  }
  
  results <- results |>
    dplyr::mutate(
      cohortEntries = formatCount(cohortEntries),
      cohortSubjects = formatCount(cohortSubjects)
    )
}


# ------------------------------------------------------------
# 4. Display results
# ------------------------------------------------------------

print(results)


# ------------------------------------------------------------
# 5. Export results
# ------------------------------------------------------------

dateStamp <- format(Sys.Date(), "%Y-%m-%d")

outputFile <- file.path(
  cohortCountsDir,
  paste0(
    outputPrefix,
    "_cohort_counts_",
    dateStamp,
    ".csv"
  )
)

write.csv(
  results,
  outputFile,
  row.names = FALSE,
  na = ""
)

message("\nCohort counts completed.")
message("Results saved to: ", outputFile)
