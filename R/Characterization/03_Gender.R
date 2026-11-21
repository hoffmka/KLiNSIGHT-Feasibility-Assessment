# ============================================================
# Cohort characterization
# 3. Gender distribution
# ============================================================
#
# Uses FeatureExtraction to compute gender distribution for
# each cohort. Output is used downstream by study-specific
# plausibility checks (e.g. KLiNSIGHT expects 100% male).
#
# ============================================================

genderSettings <- FeatureExtraction::createCovariateSettings(
  useDemographicsGender = TRUE
)

genderResults <- list()

for (i in seq_len(nrow(cohortSettings))) {

  cohortId   <- cohortSettings$cohortId[i]
  cohortName <- cohortSettings$cohortName[i]

  message("\nCharacterizing gender: ", cohortName, " (ID: ", cohortId, ")")

  covariateData <- FeatureExtraction::getDbCovariateData(
    connectionDetails    = connectionDetails,
    cdmDatabaseSchema    = cdmDatabaseSchema,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable          = cohortTable,
    cohortIds            = cohortId,
    covariateSettings    = genderSettings,
    aggregated           = TRUE
  )

  covariates    <- dplyr::collect(covariateData$covariates)
  covariateRef  <- dplyr::collect(covariateData$covariateRef)

  cohortResults <- dplyr::left_join(covariates, covariateRef, by = "covariateId") |>
    dplyr::mutate(
      cohortId   = cohortId,
      cohortName = cohortName,
      count      = sumValue,
      percentage = round(averageValue * 100, 2)
    ) |>
    dplyr::select(cohortId, cohortName, covariateId,
                  dplyr::any_of("covariateName"), count, percentage)

  genderResults[[i]] <- cohortResults
  rm(covariateData)
}

genderResults <- dplyr::bind_rows(genderResults)

outputFile <- file.path(
  characterizationDir,
  paste0("gender_", Sys.Date(), ".csv")
)
write.csv(genderResults, outputFile, row.names = FALSE, na = "")

message("\nGender characterization completed. Results saved to: ", outputFile)
print(genderResults)
