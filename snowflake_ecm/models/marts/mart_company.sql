{{
    config(
        database='dev_publish',
        schema='public',
        alias='company',
        materialized='table',
        tags=['publish', 'company']
    )
}}

/*
  Canonical company publish table.
  Priority order: iLEVEL-primary → LEVPRO-only (no iLEVEL match) → ALADDIN-only.
  Replaces INSERT OVERWRITE INTO dev_publish.public.company.
*/

WITH company_names AS (
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_aladdin_company_v3') }}    WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_ilevel_company_v3') }}     WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_levpro_company_v3') }}     WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_salesforce_company_v3') }} WHERE as_of_date = {{ as_of_date() }}
),

matches AS (
    SELECT source_system, source_company_id, source_ecm_company_id,
           target_system, target_company_id, target_ecm_company_id
    FROM {{ ref('int_company_matches_v3') }}
    WHERE as_of_date = {{ as_of_date() }} AND match_rank = 1
    UNION ALL
    SELECT target_system, target_company_id, target_ecm_company_id,
           source_system, source_company_id, source_ecm_company_id
    FROM {{ ref('int_company_matches_v3') }}
    WHERE as_of_date = {{ as_of_date() }} AND match_rank = 1
),

matches_pivoted AS (
    SELECT
        source_system, source_company_id,
        MAX(CASE WHEN target_system = 'ILEVEL'      THEN target_ecm_company_id END) AS ilevel_ecm_company_id,
        MAX(CASE WHEN target_system = 'ILEVEL'      THEN target_company_id     END) AS ilevel_company_id,
        MAX(CASE WHEN target_system = 'LEVPRO'      THEN target_ecm_company_id END) AS levpro_ecm_company_id,
        MAX(CASE WHEN target_system = 'LEVPRO'      THEN target_company_id     END) AS levpro_company_id,
        MAX(CASE WHEN target_system = 'ALADDIN'     THEN target_ecm_company_id END) AS aladdin_ecm_company_id,
        MAX(CASE WHEN target_system = 'ALADDIN'     THEN target_company_id     END) AS aladdin_company_id,
        MAX(CASE WHEN target_system = 'SALESFORCE'  THEN target_ecm_company_id END) AS salesforce_ecm_company_id,
        MAX(CASE WHEN target_system = 'SALESFORCE'  THEN target_company_id     END) AS salesforce_company_id
    FROM matches
    GROUP BY source_system, source_company_id
),

sponsor AS (
    SELECT
        c.source_system, c.source_company_id,
        COALESCE(
            c.other_attributes:sponsor_name::VARCHAR,
            MAX(d.other_attributes:sponsor_name::VARCHAR)
        ) AS sponsor_name
    FROM company_names c
    LEFT JOIN {{ ref('int_ilevel_deal_v3') }} d
        ON  d.source_system     = c.source_system
        AND d.source_company_id = c.source_company_id
        AND d.as_of_date        = {{ as_of_date() }}
    GROUP BY c.source_system, c.source_company_id, c.other_attributes:sponsor_name::VARCHAR
),

companies AS (
    SELECT
        cn.source_system, cn.source_company_id, cn.ecm_company_id,
        cn.source_company_name,
        sp.sponsor_name,
        mp.ilevel_ecm_company_id,  mp.ilevel_company_id,
        mp.levpro_ecm_company_id,  mp.levpro_company_id,
        mp.aladdin_ecm_company_id, mp.aladdin_company_id,
        mp.salesforce_ecm_company_id, mp.salesforce_company_id
    FROM company_names cn
    LEFT JOIN matches_pivoted mp
        ON  mp.source_system     = cn.source_system
        AND mp.source_company_id = cn.source_company_id
    LEFT JOIN sponsor sp
        ON  sp.source_system     = cn.source_system
        AND sp.source_company_id = cn.source_company_id
)

-- iLEVEL-primary rows
SELECT
    {{ as_of_date() }}             AS as_of_date,
    c.ecm_company_id,
    c.source_company_name          AS company_name,
    c.sponsor_name,
    c.ecm_company_id               AS ilevel_ecm_company_id,
    c.source_company_id            AS ilevel_company_id,
    c.source_company_name          AS ilevel_company_name,
    c.levpro_ecm_company_id,
    c.levpro_company_id,
    lp.source_company_name         AS levpro_company_name,
    c.aladdin_ecm_company_id,
    c.aladdin_company_id,
    al.source_company_name         AS aladdin_company_name,
    c.salesforce_ecm_company_id,
    c.salesforce_company_id,
    sf.source_company_name         AS salesforce_company_name
FROM companies c
LEFT JOIN company_names lp ON lp.source_system = 'LEVPRO'     AND lp.source_company_id = c.levpro_company_id
LEFT JOIN company_names al ON al.source_system = 'ALADDIN'    AND al.source_company_id = c.aladdin_company_id
LEFT JOIN company_names sf ON sf.source_system = 'SALESFORCE' AND sf.source_company_id = c.salesforce_company_id
WHERE c.source_system = 'ILEVEL'

UNION ALL

-- LEVPRO-only rows (no iLEVEL match)
SELECT
    {{ as_of_date() }},
    c.ecm_company_id,
    c.source_company_name,
    c.sponsor_name,
    NULL, NULL, NULL,
    c.ecm_company_id, c.source_company_id, c.source_company_name,
    c.aladdin_ecm_company_id, c.aladdin_company_id, al.source_company_name,
    c.salesforce_ecm_company_id, c.salesforce_company_id, sf.source_company_name
FROM companies c
LEFT JOIN company_names al ON al.source_system = 'ALADDIN'    AND al.source_company_id = c.aladdin_company_id
LEFT JOIN company_names sf ON sf.source_system = 'SALESFORCE' AND sf.source_company_id = c.salesforce_company_id
WHERE c.source_system = 'LEVPRO'
  AND c.ilevel_ecm_company_id IS NULL

UNION ALL

-- ALADDIN-only rows (no iLEVEL or LEVPRO match)
SELECT
    {{ as_of_date() }},
    c.ecm_company_id,
    c.source_company_name,
    NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    c.ecm_company_id, c.source_company_id, c.source_company_name,
    c.salesforce_ecm_company_id, c.salesforce_company_id, sf.source_company_name
FROM companies c
LEFT JOIN company_names sf ON sf.source_system = 'SALESFORCE' AND sf.source_company_id = c.salesforce_company_id
WHERE c.source_system = 'ALADDIN'
  AND c.ilevel_ecm_company_id IS NULL
  AND c.levpro_ecm_company_id IS NULL
