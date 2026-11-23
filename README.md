# INSiGHT-RD Diagnostic Package

This package assesses whether the clinical data required for the **INSiGHT-RD** studies can be identified at your site from your local **OMOP Common Data Model (OMOP CDM)** instance.

It is intended for **FDPG / NUM / MII community** sites participating in **NUM4Rare** or **NUM^OHDSI Connect**.

---

## What this package does

The package instantiates cohort definitions against your OMOP CDM and runs [**CohortDiagnostics**](https://ohdsi.github.io/CohortDiagnostics/) on them. CohortDiagnostics is an OHDSI tool that characterizes cohorts without exporting any patient-level data. It produces aggregated statistics on:

- how many patients are in each cohort
- which source codes triggered cohort entry (index event breakdown)
- incidence rates by year, sex, and age group
- temporal prevalence of conditions, drugs, and measurements around cohort entry
- orphan concepts — source codes related to the cohort definition that were not captured
- database metadata — CDM version, vocabulary version, and the full list of vocabularies loaded at your site

The vocabulary metadata is particularly important for the **MAScINSIGHT** study: McCune-Albright syndrome is a rare condition with limited coding coverage across vocabularies. Orphan concept analysis helps identify whether relevant codes exist in your vocabulary but were not included in the cohort definition.

The package covers two studies:

| Study | Condition |
|-------|-----------|
| **KLiNSIGHT** | Klinefelter syndrome (47,XXY) |
| **MAScINSIGHT** | McCune-Albright-Syndrom (MAS) |

You can run diagnostics for one or both studies, controlled by `STUDY_TARGET` in your `.env` file.

### Cohorts

| ID | Cohort | Study |
|----|--------|-------|
| 1 | KLiNSIGHT_basicCohort | KLiNSIGHT |
| 2 | KLiNSIGHT_basicCohort_2020plus | KLiNSIGHT |
| 3 | KLiNSIGHT_basicCohort_2020plus_labortrt | KLiNSIGHT |
| 4 | MAScINSIGHT_basicCohort | MAScINSIGHT |
| 5 | MAScINSIGHT_basicCohort_2020plus | MAScINSIGHT |

Cohorts 2 and 5 restrict to patients with a first diagnosis from 2020 onwards. Cohort 3 additionally requires at least one relevant lab measurement or treatment record. Cohort definitions (ATLAS JSON) are in `cohortsToCreate/`.

### Privacy

All outputs apply a **minimum cell count of 5**. Any count below this threshold is suppressed. No patient-level data is written or transmitted.

---

## Prerequisites

- **R ≥ 4.2**
- A JDBC-compatible database driver for your CDM (PostgreSQL, SQL Server, etc.)

All required packages are managed via [renv](https://rstudio.github.io/renv/). To install them:

```r
renv::restore()
```

This installs the exact package versions recorded in `renv.lock`. To view results locally in the Shiny explorer (optional), also install:

```r
renv::install("OHDSI/OhdsiShinyModules")
```

A PostgreSQL JDBC driver is included in `jdbcDrivers/`. For other database systems, download the appropriate driver (run once):

```r
DatabaseConnector::downloadJdbcDrivers("sql server")  # or oracle, redshift, ...
```

---

## Configuration

Copy `example.env` to `.env` in the repository root and fill in your site-specific values:

```dotenv
SITE_ID=YOUR_SITE              # Short identifier used in output file names (e.g. UMD, MHH)
DB_DBMS=postgresql             # postgresql | sql server | oracle | redshift | ...
DB_SERVER=localhost
DB_PORT=5432
DB_USER=YOUR_USER
DB_PASSWORD=YOUR_PASSWORD
DB_PATHTODRIVER=jdbcDrivers    # Path to the JDBC driver directory
CDM_SCHEMA=your_cdm_schema     # Schema containing the OMOP CDM tables
COHORT_SCHEMA=your_results_schema  # Schema where cohort tables will be written

STUDY_TARGET=BOTH              # KLINSIGHT | MASCINSIGHT | BOTH
```

> **Important:** `.env` contains credentials and must not be committed to the repository. It is listed in `.gitignore`.

---

## Running the package

Open `codeToRun.R` in RStudio or run from the repository root:

```r
source("codeToRun.R")
```

The script will:
1. Read your `.env` configuration
2. Connect to your database
3. Instantiate the cohort definitions in your `COHORT_SCHEMA`
4. Run CohortDiagnostics for all selected cohorts
5. Run study-specific plausibility checks (KLiNSIGHT)
6. Write all results to the `output/` directory and disconnect

Runtime is typically **15–30 minutes** depending on CDM size.

---

## Output

All results are written to `output/` (gitignored, never committed).

| File | Description |
|------|-------------|
| `output/cohort_diagnostics/Results_<SITE_ID>.zip` | CohortDiagnostics export — **please send this file to the study team** |
| `output/diagnostics/INSiGHT_KLiNSIGHT_diagnostics.csv` | Automated plausibility check results (PASS / WARNING / FAIL) |
| `output/unmapped_measurements.csv` | Unmapped measurement source codes (see below) — **do not share** |
| `output/unmapped_drugs.csv` | Unmapped drug source codes (see below) — **do not share** |

### Unmapped source codes

`unmapped_measurements.csv` and `unmapped_drugs.csv` list source codes from the `measurement` and `drug_exposure` tables that are not mapped to a standard OMOP concept (`concept_id = 0`). These files are intended for **local use only** to help identify gaps in your ETL or vocabulary mappings — for example, lab codes for testosterone, FSH, or LH that exist in your source system but were not mapped.

> ⚠️ These files contain aggregated source code frequencies but may be considered sensitive depending on your site's data governance rules. **Do not include them in the results package you send to the study team.**

### Reviewing results locally (optional)

You can explore the CohortDiagnostics results in an interactive Shiny app before sending:

```r
CohortDiagnostics::createMergedResultsFile(
  dataFolder   = "output/cohort_diagnostics",
  sqliteDbPath = "output/cohort_diagnostics/diagnostics_merged.sqlite"
)
CohortDiagnostics::launchDiagnosticsExplorer(
  "output/cohort_diagnostics/diagnostics_merged.sqlite"
)
```

---

## Contact

For questions or issues, please use the **Issues** section of this repository.
