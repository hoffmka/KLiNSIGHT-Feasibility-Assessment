# INSiGHT-RD Feasibility Assessment Package

This repository provides an R-based study package for the **INSiGHT-RD feasibility study**, which assesses whether the population and clinical data required for the INSiGHT-RD studies can be identified at participating sites from a local **OMOP Common Data Model (OMOP CDM)** instance.

The package is intended for **FDPG / NUM / MII community** sites participating in **NUM4Rare** and **NUM^OHDSI Connect**. It supports feasibility assessment for two studies:

| Study | Condition | Cohort definition |
|-------|-----------|-------------------|
| **KLiNSIGHT** | Klinefelter syndrome (47,XXY) | `KLiNSIGHT_basicCohort.json` |
| **MAScINSIGHT** | Mosaic 45,X/46,XY / 47,XYY | `MAScINSIGHT_basicCohort.json` |

The scope is controlled by the `STUDY_TARGET` variable in `.env` (`KLINSIGHT`, `MASCINSIGHT`, or `BOTH`).

---

## What the package does

Executing `codeToRun.R` runs four sequential steps:

### 1 — Cohort generation (`R/01_CreateCohorts.R`)

Instantiates the ATLAS cohort definitions against the local OMOP CDM using **CohortGenerator**. The cohort definitions are stored as ATLAS JSON in `cohortsToCreate/` and are compiled to OHDSI SQL locally using **CirceR** — no SQL is distributed or transmitted. The resulting cohort tables are written to the site's `COHORT_SCHEMA`.

Cohorts created (depending on `STUDY_TARGET`):

| Cohort JSON | Description |
|-------------|-------------|
| `KLiNSIGHT_basicCohort.json` | All patients with a KS (47,XXY) diagnosis code |
| `KLiNSIGHT_Klinefelter_Lab.json` | KS patients with any of the key diagnostic labs |
| `KLiNSIGHT_Klinefelter_Testosterone_Measurement.json` | KS patients with testosterone measurement |
| `KLiNSIGHT_Klinefelter_FSH_Measurement.json` | KS patients with FSH measurement |
| `KLiNSIGHT_Klinefelter_LH_Measurement.json` | KS patients with LH measurement |
| `KLiNSIGHT_Klinefelter_Testosterone_Drug.json` | KS patients with testosterone therapy |
| `KLiNSIGHT_Klinefelter_DataAvailability.json` | KS patients satisfying a broader data availability criterion |
| `MAScINSIGHT_basicCohort.json` | All patients with a MAScINSIGHT-eligible diagnosis code |

### 2 — Cohort counts (`R/02_CohortCounts.R`)

Retrieves cohort entry and subject counts for each instantiated cohort. Counts below `privacyThreshold` (default: 5) are suppressed and reported as `<5`. Results are written to `output/cohort_counts_<date>.csv`.

### 3 — CohortDiagnostics (`R/03_CohortDiagnostics.R`)

Runs **CohortDiagnostics v3.4.2** with all modules enabled:

| Module | What it produces |
|--------|-----------------|
| Index event breakdown | Which source concepts triggered cohort entry |
| Inclusion statistics | Rule-level attrition (empty here: no inclusion criteria beyond entry event) |
| Temporal characterization | Prevalence of conditions, drugs, measurements at 10 pre/post-index windows |
| Incidence rate | IR stratified by gender, age group, and calendar year |
| Orphan concepts | Source concepts close to the cohort definition that were not captured |

Results are written as CSV files to `output/cohort_diagnostics/` and packaged as `Results_<SITE_ID>.zip`.

**Reviewing results with the Shiny app:**

```r
library(CohortDiagnosticsFor)   # or CohortDiagnostics, depending on installed package

createMergedResultsFile(
  dataFolder  = "output/cohort_diagnostics",
  sqliteDbPath = "output/cohort_diagnostics/diagnostics_merged.sqlite"
)
launchDiagnosticsExplorer("output/cohort_diagnostics/diagnostics_merged.sqlite")
```

### 4 — StudyDiagnostics (`R/StudyDiagnostics/`)

Runs automated, study-specific plausibility and completeness checks. These checks read exclusively from the CohortDiagnostics CSV output — no additional database queries or characterization run is required.

---

## StudyDiagnostics checks (KLiNSIGHT)

Each check returns a one-row `data.frame` with columns `SITE_ID`, `CHECK_DATE`, `CHECK_NAME`, `CHECK_LEVEL`, `STATUS` (PASS / WARNING / FAIL), `VALUE`, and `MESSAGE`. The combined results are written to `output/diagnostics/INSiGHT_KLiNSIGHT_diagnostics.csv`.

| File | Check | Source | What it tests |
|------|-------|--------|---------------|
| `01_GenderPlausibility.R` | `KLINSIGHT_GENDER_PLAUSIBILITY` | `incidence_rate.csv` | No female patients should be in the KS cohort; female counts indicate a coding or linkage issue |
| `02_CohortEntryYearPlausibility.R` | `KLINSIGHT_ENTRY_YEAR_PLAUSIBILITY` | `incidence_rate.csv` | Distribution of cohort entries across calendar years; flags bulk imports (≥ 75 % in a single year) |
| `03_AgeGroupPlausibility.R` | `KLINSIGHT_AGE_PLAUSIBILITY` | `incidence_rate.csv` | Age distribution at cohort entry; KS presents at 10–19 (delayed puberty) and 30–39 (fertility work-up); flags unexpected 0–9 entries or peaks outside 10–64 |
| `04_IndexDiagnosisDistribution.R` | `KLINSIGHT_INDEX_DIAGNOSIS_DISTRIBUTION` | `index_event_breakdown.csv` | Which ICD/SNOMED codes drive cohort entry; identifies over-reliance on a single non-specific code |
| `05_LabAvailability.R` | `KLINSIGHT_LAB_AVAILABILITY` | `temporal_covariate_ref.csv` + `temporal_covariate_value.csv` | Whether Testosterone, FSH (Follitropin), and LH (Lutropin) are available as mapped OMOP measurement concepts; TSH reported as informative; FAIL message guides sites to check unmapped source codes |

> **Note on unmapped labs:** A FAIL or WARNING on check 05 may indicate that measurements exist in the source system but are not mapped to standard OMOP concepts (`measurement_concept_id = 0`). To investigate, query your `measurement` table for `source_value` patterns (`TESTO`, `FSH`, `LH`, `TSH`) where `measurement_concept_id = 0`.

---

## Package structure

```
.
├── codeToRun.R                        # Main entry point — run this
├── example.env                        # Configuration template → copy to .env
├── cohortsToCreate/                   # ATLAS cohort definitions (JSON)
│   ├── Cohorts.csv                    # Cohort registry (id, name, file)
│   ├── KLiNSIGHT_basicCohort.json
│   ├── KLiNSIGHT_Klinefelter_*.json   # Lab- and drug-specific sub-cohorts
│   └── MAScINSIGHT_basicCohort.json
├── R/
│   ├── 01_CreateCohorts.R             # Cohort instantiation (CohortGenerator)
│   ├── 02_CohortCounts.R              # Privacy-filtered cohort counts
│   ├── 03_CohortDiagnostics.R         # CohortDiagnostics wrapper
│   ├── 00_RunStudyAgnosticDiagnostics.R  # Study-agnostic CDM/vocabulary checks
│   └── StudyDiagnostics/
│       └── KLiNSIGHT/
│           ├── 00_RunKLiNSIGHTDiagnostics.R  # Orchestrator for checks 01–05
│           └── checks/
│               ├── 01_GenderPlausibility.R
│               ├── 02_CohortEntryYearPlausibility.R
│               ├── 03_AgeGroupPlausibility.R
│               ├── 04_IndexDiagnosisDistribution.R
│               └── 05_LabAvailability.R
└── output/                            # Created at runtime (gitignored)
    ├── cohort_counts_<date>.csv
    ├── diagnostics/
    │   └── INSiGHT_KLiNSIGHT_diagnostics.csv
    └── cohort_diagnostics/
        ├── incidence_rate.csv
        ├── temporal_covariate_value.csv
        ├── temporal_covariate_ref.csv
        ├── index_event_breakdown.csv
        ├── Results_<SITE_ID>.zip
        └── diagnostics_merged.sqlite
```

---

## Prerequisites

R ≥ 4.2 with the following packages:

```r
install.packages("remotes")
remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CohortDiagnostics")   # or CohortDiagnosticsFor
remotes::install_github("OHDSI/ParallelLogger")
install.packages("dplyr")
```

A JDBC driver for the local database must be downloaded via `DatabaseConnector::downloadJdbcDrivers()`.

---

## Configuration

Copy `example.env` to `.env` and fill in the site-specific values:

```dotenv
SITE_ID=YOUR_SITE_ACRONYM         # Short identifier used in output file names
DB_DBMS=postgresql                # postgresql | sql server | oracle | ...
DB_SERVER=localhost
DB_PORT=5432
DB_USER=YOUR_USER
DB_PASSWORD=YOUR_PASSWORD
DB_PRIVER=jdbcDrivers             # Path to JDBC driver directory
CDM_SCHEMA=your_cdm_schema
COHORT_SCHEMA=your_results_schema

STUDY_TARGET=BOTH                 # KLINSIGHT | MASCINSIGHT | BOTH
```

> The `.env` file contains credentials and **must not** be committed to the repository. It is listed in `.gitignore`.

---

## Running the package

Open `codeToRun.R` in RStudio (or run from the repository root in R):

```r
source("codeToRun.R")
```

The script reads `.env`, establishes a database connection, runs all four steps in sequence, disconnects, and writes all outputs to the `output/` directory.

**Key configurable parameters in `codeToRun.R`:**

| Variable | Default | Description |
|----------|---------|-------------|
| `privacyThreshold` | `5` | Minimum cell count for CohortDiagnostics (`minCellCount`); counts below this are suppressed |
| `studyTarget` | `"BOTH"` | Overridden from `STUDY_TARGET` in `.env` |

---

## Output summary

| File | Description |
|------|-------------|
| `output/cohort_counts_<date>.csv` | Cohort entry and subject counts, privacy-filtered |
| `output/diagnostics/INSiGHT_KLiNSIGHT_diagnostics.csv` | Automated check results (PASS/WARNING/FAIL per check) |
| `output/cohort_diagnostics/*.csv` | Full CohortDiagnostics export (incidence rates, temporal characterization, etc.) |
| `output/cohort_diagnostics/Results_<SITE_ID>.zip` | Packaged CohortDiagnostics results for the Shiny review app |

---

## Privacy

Counts below `privacyThreshold` (default: 5) are suppressed throughout all outputs. Suppressed values appear as `<5` in cohort counts and as `-5` in CohortDiagnostics CSV files. No patient-level data leaves the site.

---

## Contact

For questions, technical issues, or suggestions, please use the **Issues** section of this repository.
