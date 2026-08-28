# ============================================================
# KLiNSIGHT Feasibility Assessment
# ============================================================
#
# Feasibility assessment of the KLiNSIGHT study using the
# OMOP Common Data Model (CDM) at FDPG / MII sites.
#
# This script executes the KLiNSIGHT cohort definitions against
# a local OMOP CDM and reports the resulting cohort counts.
#
# The cohort definitions are provided as ATLAS JSON files and
# are converted to OHDSI SQL using CirceR before execution with
# CohortGenerator.
#
# ============================================================


# Optional: configure proxy if required for internet access
#
# Sys.setenv(
#   https_proxy = "http://"
# )
#
# Sys.getenv("https_proxy")
#
# Set working directory to the Study Package location
#
# setwd("~/Documents/klinsight-feasibility-assessment")

# ============================================================
# Install dependencies
# ============================================================

# Run these commands once to install the required packages.
#
# install.packages("DatabaseConnector")
# install.packages("SqlRender")
# install.packages("remotes")
# install.packages("dotenv")
#
# install.packages(
#   "CirceR",
#   repos = c(
#     "https://ohdsi.r-universe.dev",
#     "https://cloud.r-project.org"
#   )
# )
#
# remotes::install_github("OHDSI/CohortGenerator")


# ============================================================
# Load dependancies
# ============================================================

library(DatabaseConnector)
library(CirceR)
library(CohortGenerator)
library(dotenv)

# ============================================================
# Configuration
# ============================================================

# Load 

load_dot_env()

# Configure the connection to the local OMOP CDM.

# For PostgreSQL, the JDBC driver is included in the Study Package
# under "jdbcDrivers/postgresql-42.7.13".

connectionDetails <- createConnectionDetails(
  dbms = Sys.getenv("DB_DBMS"),
  server = Sys.getenv("DB_SERVER"),
  port = Sys.getenv("DB_PORT"),
  user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD"),
  pathToDriver = Sys.getenv("DB_PATHTODRIVER")
)


cdmDatabaseSchema <- Sys.getenv("CDM_SCHEMA")
cohortDatabaseSchema <- Sys.getenv("COHORT_SCHEMA")
cohortDefinitionFolder <- "cohortsToCreate"
cohortTable <- "klinsight_cohort"

# ============================================================
# Create database connection
# ============================================================

conn <- connect(connectionDetails)

cat("Connected to database.\n")

# ============================================================
# Read ATLAS cohort definitions
# ============================================================

cohortSettings <- read.csv(
  "cohortsToCreate/Cohorts.csv",
  stringsAsFactors = FALSE
)

cohortSettings

# Initialize an empty cohort definition set that will contain
# the cohort IDs, names, ATLAS JSON definitions, and generated SQL.
cohortDefinitionSet <- CohortGenerator::createEmptyCohortDefinitionSet()

# Process each cohort definition listed in Cohorts.csv.
for (i in seq_len(nrow(cohortSettings))) {
  
  cohortId <- cohortSettings$cohortId[i]
  cohortName <- cohortSettings$cohortName[i]
  
  # Locate the corresponding ATLAS JSON definition.
  jsonFile <- file.path(
    cohortDefinitionFolder,
    paste0(cohortName, ".json")
  )
  
  # Read the ATLAS cohort definition as a JSON string.
  cohortJson <- readChar(
    jsonFile,
    file.info(jsonFile)$size
  )
  
  # Convert the ATLAS JSON into a Circe cohort expression.
  cohortExpression <- CirceR::cohortExpressionFromJson(
    cohortJson
  )
  
  # Generate OHDSI SQL from the cohort expression.
  # The SQL is generated locally and can therefore be rendered
  # for the database environment of each participating site.
  cohortSql <- CirceR::buildCohortQuery(
    cohortExpression,
    options = CirceR::createGenerateOptions(
      generateStats = TRUE
    )
  )
  
  # Add the cohort definition to the cohort definition set.
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

# ============================================================
# Create cohort tables in the results schema
# ============================================================

# Get the names of the cohort tables required by CohortGenerator.
cohortTableNames <- CohortGenerator::getCohortTableNames(
  cohortTable = cohortTable
)

cohortTableNames

# Create the required cohort result tables in the local
# results schema if they do not already exist.
CohortGenerator::createCohortTables(
  connection = conn,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames = cohortTableNames
)

# ============================================================
# Generate cohorts against the local OMOP CDM
# ============================================================

# Execute all cohort definitions against the local OMOP CDM.
# The generated OHDSI SQL is rendered and executed against
# the database schema specified for the local site.
CohortGenerator::generateCohortSet(
  connection = conn,
  cdmDatabaseSchema = cdmDatabaseSchema,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames = cohortTableNames,
  cohortDefinitionSet = cohortDefinitionSet
)

# ============================================================
# Retrieve cohort counts
# ============================================================

# Retrieve the number of cohort entries and unique subjects
# generated for each cohort.
results <- CohortGenerator::getCohortCounts(
  connection = conn,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable = cohortTable
)

# ============================================================
# Include cohorts with zero subjects
# ============================================================

# Get all cohort definitions from the Study Package.
# This ensures that cohorts with no matching subjects are
# also included in the final results.
results <- CohortGenerator::getCohortCounts(
  connection = conn,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable = cohortTable
)

# Merge the observed cohort counts with the complete list
# of defined cohorts.
allCohorts <- cohortDefinitionSet[, c("cohortId", "cohortName")]

# Counts mit allen Kohorten verbinden
results <- merge(
  allCohorts,
  results,
  by = "cohortId",
  all.x = TRUE,
  sort = TRUE
)

# Replace missing counts with zero for cohorts without
# any matching subjects.
results$cohortEntries[
  is.na(results$cohortEntries)
] <- 0

results$cohortSubjects[
  is.na(results$cohortSubjects)
] <- 0

results

# ============================================================
# Save cohort results
# ============================================================

# Create the output directory if it does not already exist.
outputFolder <- "output"

if (!dir.exists(outputFolder)) {
  dir.create(outputFolder, recursive = TRUE)
}

# Add the current date to the output filename to support
# reproducibility and versioning of the generated results.
dateStamp <- format(Sys.Date(), "%Y-%m-%d")

outputFile <- file.path(
  outputFolder,
  paste0("KLiNSIGHT_cohort_results_", dateStamp, ".csv")
)

# Export the cohort counts as a CSV file.
write.csv(
  results,
  outputFile,
  row.names = FALSE
)

cat("Results saved to:", outputFile, "\n")
