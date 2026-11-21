
# ============================================================
# Cohort characterization
# Main execution
# ============================================================
#
# Controls the execution of individual characterization
# modules.
#
# ============================================================


# ------------------------------------------------------------
# 1. Validate required objects
# ------------------------------------------------------------

requiredObjects <- c(
  "connectionDetails",
  "conn",
  "cdmDatabaseSchema",
  "cohortDatabaseSchema",
  "cohortTable",
  "cohortSettings",
  "characterizationDir",
  "characterizationSettings"
)

missingObjects <- requiredObjects[
  !vapply(
    requiredObjects,
    exists,
    logical(1),
    inherits = TRUE
  )
]

if (length(missingObjects) > 0) {
  stop(
    "Missing required objects: ",
    paste(missingObjects, collapse = ", ")
  )
}


# ------------------------------------------------------------
# 2. Run selected characterization modules
# ------------------------------------------------------------

if (isTRUE(characterizationSettings$ageGroups)) {
  
  message("\nRunning: Demographics - Age groups")
  
  source(
    "R/Characterization/01_Demographics.R"
  )
}


if (isTRUE(characterizationSettings$cohortEntryYear)) {
  
  message("\nRunning: Cohort entry year")
  
  source(
    "R/Characterization/02_CohortEntryYear.R"
  )
}


if (isTRUE(characterizationSettings$gender)) {

  message("\nRunning: Demographics - Gender")

  source(
    "R/Characterization/03_Gender.R"
  )
}


# ------------------------------------------------------------
# 3. Completion
# ------------------------------------------------------------

message("\nAll selected characterizations completed.")
