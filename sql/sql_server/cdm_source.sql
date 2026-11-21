-- CDM source metadata
-- Queries the CDM_SOURCE table for version and provenance information.

SELECT
  cdm_source_name,
  cdm_source_abbreviation,
  cdm_holder,
  source_release_date,
  cdm_release_date,
  cdm_version,
  vocabulary_version
FROM @cdmDatabaseSchema.cdm_source;
