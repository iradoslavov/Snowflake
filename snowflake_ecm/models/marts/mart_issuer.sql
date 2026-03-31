{{
    config(
        database='dev_publish',
        schema='public',
        alias='issuer',
        materialized='table',
        tags=['publish', 'issuer']
    )
}}

WITH aladdin_company AS (
    SELECT source_company_id, ecm_company_id
    FROM {{ ref('int_aladdin_company_v3') }}
    WHERE as_of_date = {{ as_of_date() }}
),

-- Direct: Aladdin company already has a match in the publish company table
aladdin_direct AS (
    SELECT
        c.ecm_company_id   AS aladdin_ecm_company_id,
        p.ecm_company_id,
        p.company_name,
        CASE
            WHEN p.ilevel_ecm_company_id IS NOT NULL THEN 1
            WHEN p.levpro_ecm_company_id IS NOT NULL THEN 2
            ELSE 3
        END                AS company_priority
    FROM aladdin_company c
    JOIN {{ ref('mart_company') }} p
        ON  p.aladdin_ecm_company_id = c.ecm_company_id
),

-- Forward: Aladdin matched to iLEVEL/LEVPRO via company_matches, then to publish
aladdin_via_match_fwd AS (
    SELECT
        src_co.ecm_company_id   AS aladdin_ecm_company_id,
        p.ecm_company_id,
        p.company_name,
        CASE
            WHEN p.ilevel_ecm_company_id IS NOT NULL THEN 1
            WHEN p.levpro_ecm_company_id IS NOT NULL THEN 2
            ELSE 3
        END                     AS company_priority
    FROM {{ ref('int_company_matches_v3') }} m
    JOIN aladdin_company src_co
        ON  src_co.source_company_id = m.source_company_id
    JOIN {{ ref('mart_company') }} p
        ON  p.ilevel_ecm_company_id = m.target_ecm_company_id
         OR p.levpro_ecm_company_id = m.target_ecm_company_id
    WHERE m.as_of_date     = {{ as_of_date() }}
      AND m.source_system  = 'ALADDIN'
      AND m.target_system IN ('ILEVEL', 'LEVPRO')
      AND m.match_rank     = 1
      AND src_co.ecm_company_id NOT IN (SELECT aladdin_ecm_company_id FROM aladdin_direct)
),

-- Reverse: iLEVEL/LEVPRO matched to Aladdin (reverse direction)
aladdin_via_match_rev AS (
    SELECT
        tgt_co.ecm_company_id   AS aladdin_ecm_company_id,
        p.ecm_company_id,
        p.company_name,
        CASE
            WHEN p.ilevel_ecm_company_id IS NOT NULL THEN 1
            WHEN p.levpro_ecm_company_id IS NOT NULL THEN 2
            ELSE 3
        END                     AS company_priority
    FROM {{ ref('int_company_matches_v3') }} m
    JOIN aladdin_company tgt_co
        ON  tgt_co.source_company_id = m.target_company_id
    JOIN {{ ref('mart_company') }} p
        ON  p.ilevel_ecm_company_id = m.source_ecm_company_id
         OR p.levpro_ecm_company_id = m.source_ecm_company_id
    WHERE m.as_of_date     = {{ as_of_date() }}
      AND m.target_system  = 'ALADDIN'
      AND m.source_system IN ('ILEVEL', 'LEVPRO')
      AND m.match_rank     = 1
      AND tgt_co.ecm_company_id NOT IN (SELECT aladdin_ecm_company_id FROM aladdin_direct)
),

aladdin_to_publish AS (
    SELECT * FROM aladdin_direct
    UNION ALL
    SELECT * FROM aladdin_via_match_fwd
    WHERE aladdin_ecm_company_id NOT IN (SELECT aladdin_ecm_company_id FROM aladdin_direct)
    UNION ALL
    SELECT * FROM aladdin_via_match_rev
    WHERE aladdin_ecm_company_id NOT IN (SELECT aladdin_ecm_company_id FROM aladdin_direct)
      AND aladdin_ecm_company_id NOT IN (SELECT aladdin_ecm_company_id FROM aladdin_via_match_fwd)
)

SELECT
    {{ as_of_date() }}                               AS as_of_date,
    i.ecm_issuer_id,
    i.source_issuer_name                             AS issuer_name,
    p.ecm_company_id,
    p.company_name,
    i.source_issuer_id                               AS aladdin_issuer_id,
    (i.source_issuer_id = i.source_company_id)       AS is_top_parent
FROM {{ ref('int_aladdin_issuer_v3') }} i
JOIN aladdin_company c
    ON  c.source_company_id = i.source_company_id
LEFT JOIN aladdin_to_publish p
    ON  p.aladdin_ecm_company_id = c.ecm_company_id
WHERE i.as_of_date = {{ as_of_date() }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY i.ecm_issuer_id
    ORDER BY COALESCE(p.company_priority, 99), p.ecm_company_id
) = 1
