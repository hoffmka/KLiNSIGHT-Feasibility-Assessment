
# ============================================================
# Cohort generation
# ============================================================
#
# Reads ATLAS cohort definitions, converts them into OHDSI SQL
# and executes them against the local OMOP CDM.
#
# ============================================================


# ------------------------------------------------------------
# 1. Initialize cohort definition set
# ------------------------------------------------------------

cohortDefinitionSet <- CohortGenerator::createEmptyCohortDefinitionSet()


# ------------------------------------------------------------
# 2. Read and convert cohort definitions
# ------------------------------------------------------------

for (i in seq_len(nrow(cohortSettings))) {
  
  cohortId <- cohortSettings$cohortId[i]
  cohortName <- cohortSettings$cohortName[i]
  
  message(
    "\nProcessing cohort: ",
    cohortName,
    " (ID: ",
    cohortId,
    ")"
  )
  
  # Locate ATLAS JSON definition
  jsonFile <- file.path(
    cohortDefinitionFolder,
    paste0(cohortName, ".json")
  )
  
  if (!file.exists(jsonFile)) {
    stop("Cohort definition not found: ", jsonFile)
  }
  
  # Read JSON definition
  cohortJson <- readChar(
    jsonFile,
    file.info(jsonFile)$size
  )
  
  # Convert JSON into Circe cohort expression
  cohortExpression <- CirceR::cohortExpressionFromJson(
    cohortJson
  )
  
  # Generate OHDSI SQL
  cohortSql <- CirceR::buildCohortQuery(
    cohortExpression,
    options = CirceR::createGenerateOptions(
      generateStats = TRUE
    )
  )
  
  # Add cohort definition to definition set
  cohortDefinitionSet <- rbind(
    cohortDefinitionSet,
    data.frame(
      cohortId = cohortId,
      cohortName = cohortName,
      json = cohortJson,
      sql = cohortSql,
      stringsAsFactors = FALSE
    )
  )
}


# ------------------------------------------------------------
# 3. Create cohort result tables
# ------------------------------------------------------------

cohortTableNames <- CohortGenerator::getCohortTableNames(
  cohortTable = cohortTable
)

CohortGenerator::createCohortTables(
  connection = conn,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames = cohortTableNames
)


# ------------------------------------------------------------
# 4. Generate cohorts
# ------------------------------------------------------------

CohortGenerator::generateCohortSet(
  connection = conn,
  cdmDatabaseSchema = cdmDatabaseSchema,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames = cohortTableNames,
  cohortDefinitionSet = cohortDefinitionSet
)


# ------------------------------------------------------------
# 5. Completion
# ------------------------------------------------------------

message("\nCohort generation completed.")

print(
  cohortDefinitionSet[, c("cohortId", "cohortName")]
)
