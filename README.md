# KLiNSIGHT Feasibility Assessment

This repository contains the R-based Study Package for the **KLiNSIGHT study** to assess the feasibility of identifying the study population and relevant clinical data represented in the **OMOP Common Data Model (OMOP CDM)**.

The feasibility assessment is intended for **FDPG / MII sites** and is conducted in the context of **NUM4Rare** and **NUM^OHDSI Connect**.

## Objective

The aim is to assess whether the data required for the KLiNSIGHT study can be identified at participating sites using standardized **OHDSI/OMOP cohort definitions**.

## Workflow

The feasibility assessment is performed stepwise in an R environment with access to a local OMOP CDM instance.

1. **Set up an R environment**  
   Run the provided `codeToRun.R` script in an R environment with access to the local OMOP CDM.

2. **Install required R packages**  
   If the required packages are not already available, install `DatabaseConnector`, `CirceR`, and `CohortGenerator`. The script contains the corresponding installation commands as comments.

3. **Configure the database connection**  
   Copy `.env.example` to `.env` and enter the site-specific database configuration for the local OMOP CDM, including the database server, port, username, password, and OMOP CDM and results schemas.

   The `.env` file contains local database credentials and must **not** be committed to the repository.

4. **Run the cohort generation**  
   Execute `codeToRun.R`. The ATLAS cohort definitions included in the Study Package are converted into OHDSI SQL using `CirceR` and executed against the local OMOP CDM using `CohortGenerator`.

   During execution, the required cohort tables are created in the configured results schema of the local database. The generated cohort records are written to these tables and contain the persons who meet the respective cohort definition, together with their cohort start and end dates.

5. **Review the results**  
   The script retrieves the number of cohort entries and unique subjects identified for each cohort. Cohorts with no identified subjects are reported as `0`.

   To support privacy-preserving reporting, counts between 1 and 4 are reported as `<5`, while counts of `0` remain reported as `0`. The resulting feasibility assessment is written to the `output` directory with the current date in the filename.

The resulting output can be used to assess the availability of the KLiNSIGHT study population and relevant data elements at the respective site.

## Technical Approach

The cohort definitions are provided as **ATLAS JSON** files and are converted locally into **OHDSI SQL** using `CirceR`. The generated cohort queries are executed against the local OMOP CDM using `CohortGenerator`.

During cohort generation, `CohortGenerator` creates and populates the required cohort tables in the configured results schema. These tables are used as temporary/local results tables for the feasibility assessment and contain the cohort records generated from the study definitions. The tables remain in the local database after execution and can be removed by the local site if no longer required.

This approach allows the same study definitions to be executed across different OMOP CDM instances without distributing site-specific SQL or accessing patient-level data centrally.

## Output

The generated CSV file contains the following information for each study cohort:

- `cohortId` – identifier of the cohort
- `cohortName` – name of the cohort
- `cohortEntries` – number of cohort entries identified
- `cohortSubjects` – number of unique subjects identified

Small counts are reported as `<5` to avoid disclosure of small patient numbers. A value of `0` indicates that no subjects were identified for the respective cohort.

## Contact

For questions, technical issues, comments, or suggestions regarding this Study Package, please use the **Issues** section of this repository.