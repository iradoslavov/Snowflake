{{
    config(
        database='dev_publish',
        schema='public',
        alias='deal',
        materialized='table',
        tags=['publish', 'deal']
    )
}}

WITH deals_with_company AS (
    SELECT
        d.source_system,
        d.source_deal_id,
        d.source_deal_name,
        d.ecm_deal_id,
        d.source_company_id,
        c.ecm_company_id                                    AS source_ecm_company_id,
        d.other_attributes:sponsor_name::VARCHAR            AS sponsor_name,
        d.other_attributes:borrower_legal_name::VARCHAR     AS borrower_legal_name,
        d.other_attributes:transaction_close_date::VARCHAR  AS transaction_close_date,
        d.other_attributes:issuer_name::VARCHAR             AS issuer_name,
        cp.ecm_company_id                                   AS canonical_ecm_company_id,
        cp.company_name                                     AS canonical_company_name
    FROM {{ ref('int_ilevel_deal_v3') }} d
    JOIN {{ ref('int_ilevel_company_v3') }} c
        ON  c.source_company_id = d.source_company_id
        AND c.as_of_date        = d.as_of_date
    JOIN {{ ref('mart_company') }} cp
        ON  cp.ilevel_ecm_company_id = c.ecm_company_id
         OR cp.levpro_ecm_company_id = c.ecm_company_id
    WHERE d.as_of_date = {{ as_of_date() }}

    UNION ALL

    SELECT
        d.source_system,
        d.source_deal_id,
        d.source_deal_name,
        d.ecm_deal_id,
        d.source_company_id,
        c.ecm_company_id,
        NULL,
        NULL,
        NULL,
        d.other_attributes:issuer_name::VARCHAR,
        cp.ecm_company_id,
        cp.company_name
    FROM {{ ref('int_levpro_deal_v3') }} d
    JOIN {{ ref('int_levpro_company_v3') }} c
        ON  c.source_company_id = d.source_company_id
        AND c.as_of_date        = d.as_of_date
    JOIN {{ ref('mart_company') }} cp
        ON  cp.ilevel_ecm_company_id = c.ecm_company_id
         OR cp.levpro_ecm_company_id = c.ecm_company_id
    WHERE d.as_of_date = {{ as_of_date() }}
),

security_spine AS (
    SELECT DISTINCT source_system, source_company_id, aladdin_id
    FROM {{ ref('int_ilevel_security_v3') }}
    WHERE as_of_date = {{ as_of_date() }} AND aladdin_id IS NOT NULL
    UNION ALL
    SELECT DISTINCT source_system, source_company_id, aladdin_id
    FROM {{ ref('int_levpro_security_v3') }}
    WHERE as_of_date = {{ as_of_date() }} AND aladdin_id IS NOT NULL
),

levpro_suppressed AS (
    SELECT DISTINCT lp.ecm_deal_id AS levpro_ecm_deal_id
    FROM deals_with_company lp
    JOIN deals_with_company il
        ON  il.source_system            = 'ILEVEL'
        AND il.canonical_ecm_company_id = lp.canonical_ecm_company_id
    JOIN security_spine sl
        ON  sl.source_system     = 'LEVPRO'
        AND sl.source_company_id = lp.source_company_id
    JOIN security_spine si
        ON  si.source_system     = 'ILEVEL'
        AND si.source_company_id = il.source_company_id
        AND si.aladdin_id        = sl.aladdin_id
    WHERE lp.source_system = 'LEVPRO'
),

ilevel_levpro_xref AS (
    SELECT
        il.ecm_deal_id                    AS ilevel_ecm_deal_id,
        lp.ecm_deal_id                    AS levpro_ecm_deal_id,
        lp.source_deal_id                 AS levpro_deal_id,
        lp.source_deal_name               AS levpro_deal_name,
        COUNT(DISTINCT si.aladdin_id)     AS shared_count
    FROM deals_with_company il
    JOIN deals_with_company lp
        ON  lp.source_system            = 'LEVPRO'
        AND lp.canonical_ecm_company_id = il.canonical_ecm_company_id
    JOIN security_spine si
        ON  si.source_system     = 'ILEVEL'
        AND si.source_company_id = il.source_company_id
    JOIN security_spine sl
        ON  sl.source_system     = 'LEVPRO'
        AND sl.source_company_id = lp.source_company_id
        AND sl.aladdin_id        = si.aladdin_id
    WHERE il.source_system = 'ILEVEL'
    GROUP BY il.ecm_deal_id, lp.ecm_deal_id, lp.source_deal_id, lp.source_deal_name
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY il.ecm_deal_id
        ORDER BY shared_count DESC, lp.source_deal_id
    ) = 1
)

-- iLEVEL deals with LEVPRO cross-reference
SELECT
    {{ as_of_date() }},
    d.ecm_deal_id, d.source_deal_name,
    d.canonical_ecm_company_id, d.canonical_company_name,
    d.ecm_deal_id, d.source_deal_id, d.source_deal_name,
    xr.levpro_ecm_deal_id, xr.levpro_deal_id, xr.levpro_deal_name,
    d.sponsor_name, d.borrower_legal_name, d.transaction_close_date
FROM deals_with_company d
LEFT JOIN ilevel_levpro_xref xr ON xr.ilevel_ecm_deal_id = d.ecm_deal_id
WHERE d.source_system = 'ILEVEL'

UNION ALL

-- LEVPRO-only deals (not suppressed by an iLEVEL match)
SELECT
    {{ as_of_date() }},
    d.ecm_deal_id, d.source_deal_name,
    d.canonical_ecm_company_id, d.canonical_company_name,
    NULL, NULL, NULL,
    d.ecm_deal_id, d.source_deal_id, d.source_deal_name,
    NULL, d.issuer_name, NULL
FROM deals_with_company d
WHERE d.source_system = 'LEVPRO'
  AND d.ecm_deal_id NOT IN (SELECT levpro_ecm_deal_id FROM levpro_suppressed)
