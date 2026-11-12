
# ============================================================
# Cohort characterization
# 1. Demographics: Age groups
# ============================================================
#
# Characterizes the age distribution at cohort start.
# Age groups are defined in 5-year intervals.
#
# ============================================================


# ------------------------------------------------------------
# 1. Define covariate settings
# ------------------------------------------------------------

ageGroupSettings <- FeatureExtraction::createCovariateSettings(
  useDemographicsAgeGroup = TRUE
)


# ------------------------------------------------------------
# 2. Characterize cohorts
# ------------------------------------------------------------

ageGroupResults <- list()

for (i in seq_len(nrow(cohortSettings))) {
  
  cohortId <- cohortSettings$cohortId[i]
  cohortName <- cohortSettings$cohortName[i]
  
  message(
    "\nCharacterizing cohort: ",
    cohortName,
    " (ID: ",
    cohortId,
    ")"
  )
  
  # Generate aggregated age group covariates
  covariateData <- FeatureExtraction::getDbCovariateData(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmDatabaseSchema,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable = cohortTable,
    cohortIds = cohortId,
    covariateSettings = ageGroupSettings,
    aggregated = TRUE
  )
  
  # Retrieve covariates
  covariates <- covariateData$covariates |>
    dplyr::collect()
  
  # Retrieve covariate descriptions
  covariateRef <- covariateData$covariateRef |>
    dplyr::collect()
  
  # Combine results
  cohortResults <- covariates |>
    dplyr::left_join(
      covariateRef,
      by = "covariateId"
    ) |>
    dplyr::mutate(
      cohortId = cohortId,
      cohortName = cohortName,
      count = sumValue,
      percentage = averageValue * 100
    ) |>
    dplyr::select(
      cohortId,
      cohortName,
      covariateId,
      dplyr::any_of("covariateName"),
      count,
      percentage
    )
  
  ageGroupResults[[i]] <- cohortResults
  
  # Release memory
  rm(covariateData)
  
}


# ------------------------------------------------------------
# 3. Combine results
# ------------------------------------------------------------

ageGroupResults <- dplyr::bind_rows(
  ageGroupResults
)


# ------------------------------------------------------------
# 4. Export results
# ------------------------------------------------------------

outputFile <- file.path(
  characterizationDir,
  paste0(
    "age_groups_",
    Sys.Date(),
    ".csv"
  )
)

write.csv(
  ageGroupResults,
  outputFile,
  row.names = FALSE,
  na = ""
)

message("\nAge group characterization completed.")
message("Results saved to: ", outputFile)

print(ageGroupResults)
