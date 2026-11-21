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
#   https_proxy = "https://"
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
# install.packages("renv", repos = "https://cloud.r-project.org")
# 
# renv::init()
# renv::restore()
# 
# install.packages("DatabaseConnector")
# install.packages("SqlRender")
# install.packages("remotes")
# install.packages("dotenv")
# install.packages("CirceR")
# install.packages("FeatureExtraction")
# 
# remotes::install_github("OHDSI/CohortGenerator")
# remotes::install_github("OHDSI/CohortDiagnostics")
# 
# renv::snapshot()

renv::restore()

# ============================================================
# Load dependencies
# ============================================================

library(DatabaseConnector)
library(CirceR)
library(CohortGenerator)
library(CohortDiagnostics)
library(dotenv)

# ============================================================
# 1. Configuration
# ============================================================

# Load environment variables
dotenv::load_dot_env()

# Database configuration

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

siteId               <- Sys.getenv("SITE_ID")
cdmDatabaseSchema    <- Sys.getenv("CDM_SCHEMA")
cohortDatabaseSchema <- Sys.getenv("COHORT_SCHEMA")

# Study target — controls cohort generation, characterization,
# and study-specific diagnostics.
# Valid values: "KLINSIGHT" | "MASCINSIGHT" | "BOTH"
studyTarget <- toupper(trimws(Sys.getenv("STUDY_TARGET", unset = "BOTH")))
if (!studyTarget %in% c("KLINSIGHT", "MASCINSIGHT", "BOTH")) {
  stop(sprintf(
    "Invalid STUDY_TARGET '%s' in .env. Must be KLINSIGHT, MASCINSIGHT, or BOTH.",
    studyTarget
  ))
}
message(sprintf("Study target: %s", studyTarget))

# Map study names to cohort IDs (matches cohortsToCreate/Cohorts.csv)
studyCohortIds <- list(
  KLINSIGHT   = 1L,
  MASCINSIGHT = 2L
)

# Cohort configuration
cohortDefinitionFolder <- "cohortsToCreate"
cohortTable <- "insight_cohort"

cohortSettings <- read.csv(
  "cohortsToCreate/Cohorts.csv",
  stringsAsFactors = FALSE
)

# Keep only cohorts belonging to the selected study
activeCohortIds <- if (studyTarget == "BOTH") {
  unlist(studyCohortIds, use.names = FALSE)
} else {
  studyCohortIds[[studyTarget]]
}
cohortSettings <- cohortSettings[cohortSettings$cohortId %in% activeCohortIds, ]
message(sprintf("Active cohorts: %s",
                paste(cohortSettings$cohortName, collapse = ", ")))

# Output configuration
outputDir <- "output"
outputPrefix <- "INSiGHT"

outputFolderDiagnostics <- file.path(outputDir, "Diagnostics")

cohortCountsDir <- file.path(outputDir, "cohort_counts")

cohortDiagnosticsDir <- file.path(outputDir, "cohort_diagnostics")

# Privacy settings
suppressSmallCounts <- TRUE
privacyThreshold <- 5

# ------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------

dir.create(outputFolderDiagnostics, recursive = TRUE, showWarnings = FALSE)
dir.create(cohortCountsDir,         recursive = TRUE, showWarnings = FALSE)
dir.create(cohortDiagnosticsDir,    recursive = TRUE, showWarnings = FALSE)

# ============================================================
# Create database connection
# ============================================================

conn <- DatabaseConnector::connect(connectionDetails)

# ============================================================
# Generate cohorts
# ============================================================

source("R/01_CreateCohorts.R")

# ============================================================
# Calculate cohort counts
# ============================================================

source("R/02_CohortCounts.R")

# ============================================================
# Run CohortDiagnostics
# ============================================================

source("R/03_CohortDiagnostics.R")
runCohortDiagnostics(
  cohortDefinitionSet  = cohortDefinitionSet,
  connectionDetails    = connectionDetails,
  cdmDatabaseSchema    = cdmDatabaseSchema,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable          = cohortTable,
  cohortDiagnosticsDir = cohortDiagnosticsDir,
  siteId               = siteId,
  privacyThreshold     = privacyThreshold
)


# # Build SQLite-DB from ZIP
# CohortDiagnostics::preMergeDiagnosticsFiles(
#   dataFolder = "output/cohort_diagnostics",
#   sqliteDbPath = "output/cohort_diagnostics/diagnostics_merged.sqlite"
# )
# 
# # Start Shiny Explorer
# CohortDiagnostics::launchDiagnosticsExplorer(
#   sqliteDbPath = "output/cohort_diagnostics/diagnostics_merged.sqlite"
# )


# ============================================================
# Custom diagnostics
# ============================================================

if (studyTarget %in% c("KLINSIGHT", "BOTH")) {
  source(file.path("R", "StudyDiagnostics", "KLiNSIGHT", "00_RunKLiNSIGHTDiagnostics.R"))
  klinsightDiagResults <- runKLiNSIGHTDiagnostics(
    cohortDiagnosticsDir = cohortDiagnosticsDir,
    outputFolder         = outputFolderDiagnostics,
    siteId               = siteId
  )
}

if (studyTarget %in% c("MASCINSIGHT", "BOTH")) {
  # MAScINSIGHT study-specific diagnostics — not yet implemented
  # source(file.path("R", "StudyDiagnostics", "MAScINSIGHT", "00_RunMAScINSIGHTDiagnostics.R"))
  message("MAScINSIGHT study-specific diagnostics: not yet implemented.")
}


# Check if measurements and drugs are not mapped to standard concepts (concept_id=0 within the cohorts)
source(file.path("R", "explore_unmapped_source_codes.R"))

# All cohorts (from Cohorts.csv):
meas <- getUnmappedMeasurements()
drug <- getUnmappedDrugExposures()

# Single cohort, write directly to CSV:
meas <- getUnmappedMeasurements(cohortDefinitionId = 1L, minCount = 1L,
                                outputFile = file.path("output", "unmapped_measurements.csv"))
drug <- getUnmappedDrugExposures(cohortDefinitionId = 1L, minCount = 1L,
                                 outputFile = file.path("output", "unmapped_drugs.csv"))

# ============================================================
# Close database connection
# ============================================================

DatabaseConnector::disconnect(conn)
message("Database connection closed.")
