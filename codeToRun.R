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
# 
# renv::snapshot()

renv::restore()

# ============================================================
# Load dependancies
# ============================================================

library(DatabaseConnector)
library(CirceR)
library(CohortGenerator)
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

cdmDatabaseSchema <- Sys.getenv("CDM_SCHEMA")
cohortDatabaseSchema <- Sys.getenv("COHORT_SCHEMA")

#Cohort configuration
cohortDefinitionFolder <- "cohortsToCreate"
cohortTable <- "insight_cohort"

cohortSettings <- read.csv(
  "cohortsToCreate/Cohorts.csv",
  stringsAsFactors = FALSE
)

# Output configuration
outputDir <- "output"
outputPrefix <- "INSiGHT"

cohortCountsDir <- file.path(
  outputDir,
  "cohort_counts"
)

characterizationDir <- file.path(
  outputDir,
  "characterization"
)

# Privacy settings
suppressSmallCounts <- TRUE
privacyThreshold <- 5

# Characterization selection
characterizationSettings <- list(
  ageGroups = TRUE,
  cohortEntryYear = TRUE
)

# ------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------

dir.create(
  cohortCountsDir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  characterizationDir,
  recursive = TRUE,
  showWarnings = FALSE
)

# ============================================================
# Create database connection
# ============================================================

conn <- DatabaseConnector::connect(
  connectionDetails
)

cat("Connected to database.\n")


# ============================================================
# Generate cohorts
# ============================================================

source("R/01_CreateCohorts.R")

# ============================================================
# Calculate cohort counts
# ============================================================

source("R/02_CohortCounts.R")

# ============================================================
# Run cohort characterization
# ============================================================

source("R/Characterization/00_RunCharacterization.R")

# Close database connection
DatabaseConnector::disconnect(conn)

message("Database connection closed.")

