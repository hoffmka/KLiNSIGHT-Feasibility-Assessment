# INSiGHT-RD Feasibility Assessment

R study package for assessing data availability at OMOP CDM sites for the **KLiNSIGHT** (Klinefelter, 47,XXY) and **MAScINSIGHT** (Mosaic 45,X/46,XY / 47,XYY) studies.

---

## Setup

**1. Install dependencies**

```r
remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/FeatureExtraction")
remotes::install_github("OHDSI/CohortDiagnostics")
```

Download a JDBC driver for your database:
```r
DatabaseConnector::downloadJdbcDrivers("postgresql")  # or your DBMS
```

**2. Configure**

Copy `example.env` to `.env` and fill in your site values:

```dotenv
SITE_ID=YOUR_SITE
DB_DBMS=postgresql
DB_SERVER=localhost
DB_PORT=5432
DB_USER=...
DB_PASSWORD=...
DB_PATHTODRIVER=jdbcDrivers    # path to JDBC driver directory
CDM_SCHEMA=your_cdm_schema
COHORT_SCHEMA=your_results_schema
STUDY_TARGET=BOTH              # KLINSIGHT | MASCINSIGHT | BOTH
```

**3. Run**

```r
source("codeToRun.R")
```

---

## Cohorts

| ID | Name | Study |
|----|------|-------|
| 1 | KLiNSIGHT_basicCohort | KLiNSIGHT |
| 2 | KLiNSIGHT_basicCohort_2020plus | KLiNSIGHT |
| 3 | KLiNSIGHT_basicCohort_2020plus_labortrt | KLiNSIGHT |
| 4 | MAScINSIGHT_basicCohort | MAScINSIGHT |
| 5 | MAScINSIGHT_basicCohort_2020plus | MAScINSIGHT |

Cohort definitions (ATLAS JSON) are in `cohortsToCreate/`.

---

## Output

All results are written to `output/` (gitignored). Counts below 5 are suppressed.

| File | Content |
|------|---------|
| `cohort_counts_<date>.csv` | Entry and subject counts |
| `cohort_diagnostics/Results_<SITE_ID>.zip` | CohortDiagnostics export |
| `diagnostics/INSiGHT_KLiNSIGHT_diagnostics.csv` | Automated plausibility checks |

To review CohortDiagnostics results:
```r
CohortDiagnostics::createMergedResultsFile(
  dataFolder   = "output/cohort_diagnostics",
  sqliteDbPath = "output/cohort_diagnostics/diagnostics_merged.sqlite"
)
CohortDiagnostics::launchDiagnosticsExplorer(
  "output/cohort_diagnostics/diagnostics_merged.sqlite"
)
```
