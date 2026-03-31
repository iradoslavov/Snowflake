{{
    config(materialized='ephemeral')
}}

/*
  Shared base subquery for all three ALADDIN entity models
  (company_v3, issuer_v3, security_v3).

  The original script used a single INSERT ALL SELECT to fan out into three
  tables in one pass.  dbt cannot do multi-table inserts, so this ephemeral
  model is inlined as a CTE into each of the three downstream models,
  filtered on rn_company / rn_issuer / rn_security respectively.

  Oracle-style (+) outer joins have been rewritten as ANSI LEFT JOINs.
*/

WITH active_positions AS (
    SELECT DISTINCT aladdin_id
    FROM {{ source('aladdin_share', 'pos_analytics') }}
    WHERE pos_date > DATEADD(MONTH, -12, {{ as_of_date() }})
)

SELECT
    'ALADDIN'                                                          AS source_system,
    sm.aladdin_id                                                      AS source_security_id,
    sm.aladdin_id                                                      AS aladdin_id,
    x.identifier                                                       AS client_id,
    NVL(iss.issuer_id,     'No Issuer')                                AS source_issuer_id,
    iss.issuer_long_name                                               AS source_issuer_name,
    NVL(iss_ult.issuer_id, 'No Company')                               AS source_company_id,
    iss_ult.issuer_long_name                                           AS source_company_name,
    ROW_NUMBER() OVER (PARTITION BY iss_ult.issuer_id ORDER BY 1)     AS rn_company,
    ROW_NUMBER() OVER (PARTITION BY iss.issuer_id     ORDER BY 1)     AS rn_issuer,
    ROW_NUMBER() OVER (PARTITION BY sm.aladdin_id     ORDER BY 1)     AS rn_security
FROM active_positions p
JOIN {{ source('aladdin_share', 'security_master') }} sm
    ON  sm.aladdin_id = p.aladdin_id
LEFT JOIN {{ ref('stg_adc_ids') }} x
    ON  x.aladdin_id = sm.aladdin_id
LEFT JOIN {{ source('aladdin_share', 'issuers') }} iss
    ON  iss.issuer_id = sm.issuer_id
LEFT JOIN {{ source('aladdin_share', 'issuers') }} iss_ult
    ON  iss_ult.issuer_id = iss.ultimate_parent_issuer_id
