{{
    config(
        database='dev_publish',
        schema='public',
        alias='security',
        materialized='table',
        tags=['publish', 'security']
    )
}}

WITH aladdin_sec AS (
    SELECT
        source_security_id  AS aladdin_security_id,
        aladdin_id,
        client_id           AS aladdin_client_id,
        ecm_security_id,
        source_issuer_id    AS aladdin_issuer_id,
        source_company_id   AS aladdin_company_id
    FROM {{ ref('int_aladdin_security_v3') }}
    WHERE as_of_date = {{ as_of_date() }}
),

ilevel_sec AS (
    SELECT
        ecm_security_id     AS ilevel_ecm_security_id,
        aladdin_id,
        client_id           AS ilevel_client_id,
        source_company_id   AS ilevel_company_id
    FROM {{ ref('int_ilevel_security_v3') }}
    WHERE as_of_date = {{ as_of_date() }}
      AND aladdin_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY aladdin_id ORDER BY source_security_id) = 1
),

levpro_sec AS (
    SELECT
        ecm_security_id     AS levpro_ecm_security_id,
        aladdin_id,
        client_id           AS levpro_client_id,
        source_company_id   AS levpro_company_id
    FROM {{ ref('int_levpro_security_v3') }}
    WHERE as_of_date = {{ as_of_date() }}
      AND aladdin_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY aladdin_id ORDER BY source_security_id) = 1
),

ilevel_company_map AS (
    SELECT c.source_company_id AS ilevel_source_company_id, cp.ecm_company_id
    FROM {{ ref('int_ilevel_company_v3') }} c
    JOIN {{ ref('mart_company') }} cp ON cp.ilevel_ecm_company_id = c.ecm_company_id
    WHERE c.as_of_date = {{ as_of_date() }}
),

levpro_company_map AS (
    SELECT c.source_company_id AS levpro_source_company_id, cp.ecm_company_id
    FROM {{ ref('int_levpro_company_v3') }} c
    JOIN {{ ref('mart_company') }} cp ON cp.levpro_ecm_company_id = c.ecm_company_id
    WHERE c.as_of_date = {{ as_of_date() }}
),

ilevel_deal AS (
    SELECT il.aladdin_id, dp.ecm_deal_id, dp.deal_name
    FROM ilevel_sec il
    JOIN ilevel_company_map cm ON cm.ilevel_source_company_id = il.ilevel_company_id
    JOIN {{ ref('int_ilevel_security_v3') }} ds
        ON  ds.aladdin_id        = il.aladdin_id
        AND ds.source_company_id = il.ilevel_company_id
        AND ds.as_of_date        = {{ as_of_date() }}
    JOIN {{ ref('int_ilevel_deal_v3') }} dv
        ON  dv.source_company_id = ds.source_company_id
        AND dv.as_of_date        = {{ as_of_date() }}
    JOIN {{ ref('mart_deal') }} dp
        ON  dp.ilevel_deal_id = dv.source_deal_id
        AND dp.ecm_company_id = cm.ecm_company_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY il.aladdin_id ORDER BY dp.ecm_deal_id) = 1
),

levpro_deal AS (
    SELECT lp.aladdin_id, dp.ecm_deal_id, dp.deal_name
    FROM levpro_sec lp
    JOIN levpro_company_map cm ON cm.levpro_source_company_id = lp.levpro_company_id
    JOIN {{ ref('int_levpro_security_v3') }} ds
        ON  ds.aladdin_id        = lp.aladdin_id
        AND ds.source_company_id = lp.levpro_company_id
        AND ds.as_of_date        = {{ as_of_date() }}
    JOIN {{ ref('int_levpro_deal_v3') }} dv
        ON  dv.source_company_id = ds.source_company_id
        AND dv.as_of_date        = {{ as_of_date() }}
    JOIN {{ ref('mart_deal') }} dp
        ON  dp.levpro_deal_id = dv.source_deal_id
        AND dp.ecm_company_id = cm.ecm_company_id
    WHERE lp.aladdin_id NOT IN (SELECT aladdin_id FROM ilevel_deal)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY lp.aladdin_id ORDER BY dp.ecm_deal_id) = 1
),

best_deal AS (
    SELECT * FROM ilevel_deal
    UNION ALL
    SELECT * FROM levpro_deal
)

SELECT
    {{ as_of_date() }}                                                            AS as_of_date,
    a.ecm_security_id,
    a.aladdin_id,
    COALESCE(a.aladdin_client_id, il.ilevel_client_id, lp.levpro_client_id)      AS client_id,
    iss.ecm_issuer_id,
    iss.issuer_name,
    bd.ecm_deal_id,
    bd.deal_name,
    il.ilevel_ecm_security_id,
    lp.levpro_ecm_security_id
FROM aladdin_sec a
LEFT JOIN ilevel_sec il   ON  il.aladdin_id           = a.aladdin_id
LEFT JOIN levpro_sec lp   ON  lp.aladdin_id           = a.aladdin_id
LEFT JOIN {{ ref('mart_issuer') }} iss
    ON  iss.aladdin_issuer_id = a.aladdin_issuer_id
LEFT JOIN best_deal bd    ON  bd.aladdin_id           = a.aladdin_id
