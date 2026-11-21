-- Adapted from darwin-eu/CdmOnboarding (Apache 2.0)
-- Returns concept counts per vocabulary including version.
-- Row where ID = 'None' holds the overall OMOP vocabulary bundle version.

SELECT
  v.vocabulary_id      AS ID,
  v.vocabulary_name    AS NAME,
  v.vocabulary_version AS VERSION,
  SUM(CASE WHEN c.standard_concept = 'S'   THEN 1 ELSE 0 END) AS N_STANDARD_CONCEPTS,
  SUM(CASE WHEN c.standard_concept = 'C'   THEN 1 ELSE 0 END) AS N_CLASSIFICATION_CONCEPTS,
  SUM(CASE WHEN ISNULL(c.standard_concept, '') = '' THEN 1 ELSE 0 END) AS N_NON_STANDARD_CONCEPTS
FROM @cdmDatabaseSchema.vocabulary v
LEFT JOIN @cdmDatabaseSchema.concept c
  ON c.vocabulary_id = v.vocabulary_id
GROUP BY v.vocabulary_id, v.vocabulary_name, v.vocabulary_version
ORDER BY v.vocabulary_id;
