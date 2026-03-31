{{
    config(
        database='dev_curate',
        schema='core',
        alias='company_matches_v3',
        materialized='table',
        tags=['matching']
    )
}}

/*
  Two-pass company matching:
    Pass 1 — ALADDIN_ID / CLIENT_ID exact matches across ALADDIN / ILEVEL / LEVPRO
    Pass 2 — Fuzzy name match (Jaro-Winkler >= 99) against SALESFORCE

  Both passes are unioned and ranked within this single model.
  This replaces the two separate INSERT INTO company_matches_v3 blocks.
*/

-- ── Shared base views ────────────────────────────────────────────────────────

WITH co_ald AS (
    SELECT DISTINCT source_system, source_company_id, aladdin_id
    FROM {{ ref('int_aladdin_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND aladdin_id    IS NOT NULL
    UNION ALL
    SELECT DISTINCT source_system, source_company_id, aladdin_id
    FROM {{ ref('int_ilevel_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND aladdin_id    IS NOT NULL
    UNION ALL
    SELECT DISTINCT source_system, source_company_id, aladdin_id
    FROM {{ ref('int_levpro_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND aladdin_id    IS NOT NULL
),

co_cli AS (
    SELECT DISTINCT source_system, source_company_id, client_id
    FROM {{ ref('int_aladdin_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND client_id     IS NOT NULL
    UNION ALL
    SELECT DISTINCT source_system, source_company_id, client_id
    FROM {{ ref('int_ilevel_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND client_id     IS NOT NULL
    UNION ALL
    SELECT DISTINCT source_system, source_company_id, client_id
    FROM {{ ref('int_levpro_security_v3') }}
    WHERE as_of_date    = {{ as_of_date() }}
      AND client_id     IS NOT NULL
),

-- ── Pass 1: ID-based matches ─────────────────────────────────────────────────

ald_matches AS (
    SELECT
        a.source_system, a.source_company_id,
        b.source_system AS target_system, b.source_company_id AS target_company_id,
        'ALADDIN_ID'    AS match_basis,
        a.aladdin_id    AS match_value
    FROM co_ald a
    JOIN co_ald b
        ON  a.aladdin_id     = b.aladdin_id
        AND a.source_system != b.source_system
),

cli_matches AS (
    SELECT
        a.source_system, a.source_company_id,
        b.source_system AS target_system, b.source_company_id AS target_company_id,
        'CLIENT_ID'     AS match_basis,
        a.client_id     AS match_value
    FROM co_cli a
    JOIN co_cli b
        ON  a.client_id      = b.client_id
        AND a.source_system != b.source_system
    WHERE NOT EXISTS (
        SELECT 1 FROM ald_matches x
        WHERE x.source_system     = a.source_system
          AND x.source_company_id = a.source_company_id
          AND x.target_system     = b.source_system
          AND x.target_company_id = b.source_company_id
    )
),

id_matches_agg AS (
    SELECT
        source_system, source_company_id, target_system, target_company_id, match_basis,
        LISTAGG(DISTINCT match_value, '; ') WITHIN GROUP (ORDER BY match_value) AS match_value,
        NULL::FLOAT   AS match_score,
        NULL::VARCHAR AS match_col_source,
        NULL::VARCHAR AS match_col_target
    FROM (SELECT * FROM ald_matches UNION ALL SELECT * FROM cli_matches)
    GROUP BY source_system, source_company_id, target_system, target_company_id, match_basis
),

-- ── Pass 2: Fuzzy name match to SALESFORCE ────────────────────────────────────

company_names AS (
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_aladdin_company_v3') }}   WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_ilevel_company_v3') }}    WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_levpro_company_v3') }}    WHERE as_of_date = {{ as_of_date() }}
    UNION ALL
    SELECT source_system, source_company_id, ecm_company_id, source_company_name
    FROM {{ ref('int_salesforce_company_v3') }} WHERE as_of_date = {{ as_of_date() }}
),

non_sf AS (
    SELECT
        c.source_system, c.source_company_id, c.source_company_name,
        MAX(d.other_attributes:borrower_legal_name::VARCHAR) AS borrower_legal_name,
        MAX(d.other_attributes:issuer_name::VARCHAR)         AS issuer_name,
        MAX(d.other_attributes:sponsor_name::VARCHAR)        AS sponsor_name
    FROM company_names c
    LEFT JOIN {{ ref('int_ilevel_deal_v3') }} d
        ON  d.source_system     = c.source_system
        AND d.source_company_id = c.source_company_id
        AND d.as_of_date        = {{ as_of_date() }}
    WHERE c.source_system IN ('ALADDIN', 'ILEVEL', 'LEVPRO')
    GROUP BY c.source_system, c.source_company_id, c.source_company_name
),

sf AS (
    SELECT source_company_id AS sf_id, source_company_name AS sf_name
    FROM company_names
    WHERE source_system = 'SALESFORCE'
),

scored AS (
    SELECT n.source_system, n.source_company_id, sf.sf_id, sf.sf_name,
           'source_company_name' AS match_col_source, 'source_company_name' AS match_col_target,
           n.source_company_name AS match_value,
           JAROWINKLER_SIMILARITY(UPPER(TRIM(n.source_company_name)), UPPER(TRIM(sf.sf_name)))::FLOAT AS match_score
    FROM non_sf n CROSS JOIN sf
    WHERE n.source_company_name IS NOT NULL
      AND JAROWINKLER_SIMILARITY(UPPER(TRIM(n.source_company_name)), UPPER(TRIM(sf.sf_name))) >= 99

    UNION ALL
    SELECT n.source_system, n.source_company_id, sf.sf_id, sf.sf_name,
           'borrower_legal_name', 'source_company_name', n.borrower_legal_name,
           JAROWINKLER_SIMILARITY(UPPER(TRIM(n.borrower_legal_name)), UPPER(TRIM(sf.sf_name)))::FLOAT
    FROM non_sf n CROSS JOIN sf
    WHERE n.borrower_legal_name IS NOT NULL
      AND JAROWINKLER_SIMILARITY(UPPER(TRIM(n.borrower_legal_name)), UPPER(TRIM(sf.sf_name))) >= 99

    UNION ALL
    SELECT n.source_system, n.source_company_id, sf.sf_id, sf.sf_name,
           'issuer_name', 'source_company_name', n.issuer_name,
           JAROWINKLER_SIMILARITY(UPPER(TRIM(n.issuer_name)), UPPER(TRIM(sf.sf_name)))::FLOAT
    FROM non_sf n CROSS JOIN sf
    WHERE n.issuer_name IS NOT NULL
      AND JAROWINKLER_SIMILARITY(UPPER(TRIM(n.issuer_name)), UPPER(TRIM(sf.sf_name))) >= 99

    UNION ALL
    SELECT n.source_system, n.source_company_id, sf.sf_id, sf.sf_name,
           'sponsor_name', 'source_company_name', n.sponsor_name,
           JAROWINKLER_SIMILARITY(UPPER(TRIM(n.sponsor_name)), UPPER(TRIM(sf.sf_name)))::FLOAT
    FROM non_sf n CROSS JOIN sf
    WHERE n.sponsor_name IS NOT NULL
      AND JAROWINKLER_SIMILARITY(UPPER(TRIM(n.sponsor_name)), UPPER(TRIM(sf.sf_name))) >= 99
),

-- ── Combine & rank both passes ────────────────────────────────────────────────

all_matches AS (
    -- Pass 1
    SELECT
        {{ as_of_date() }}       AS as_of_date,
        m.source_system,
        m.source_company_id,
        src_co.ecm_company_id    AS source_ecm_company_id,
        m.target_system,
        m.target_company_id,
        tgt_co.ecm_company_id    AS target_ecm_company_id,
        m.match_basis,
        m.match_col_source,
        m.match_col_target,
        m.match_value,
        m.match_score
    FROM id_matches_agg m
    LEFT JOIN company_names src_co
        ON  src_co.source_system     = m.source_system
        AND src_co.source_company_id = m.source_company_id
    LEFT JOIN company_names tgt_co
        ON  tgt_co.source_system     = m.target_system
        AND tgt_co.source_company_id = m.target_company_id

    UNION ALL

    -- Pass 2
    SELECT
        {{ as_of_date() }},
        s.source_system,
        s.source_company_id,
        src_co.ecm_company_id,
        'SALESFORCE',
        s.sf_id,
        tgt_co.ecm_company_id,
        'NAME_MATCH',
        s.match_col_source,
        s.match_col_target,
        s.match_value,
        s.match_score
    FROM scored s
    LEFT JOIN company_names src_co
        ON  src_co.source_system     = s.source_system
        AND src_co.source_company_id = s.source_company_id
    LEFT JOIN company_names tgt_co
        ON  tgt_co.source_system     = 'SALESFORCE'
        AND tgt_co.source_company_id = s.sf_id
)

SELECT
    as_of_date,
    source_system,
    source_company_id,
    source_ecm_company_id,
    target_system,
    target_company_id,
    target_ecm_company_id,
    ROW_NUMBER() OVER (
        PARTITION BY source_system, source_company_id, target_system
        ORDER BY
            CASE match_basis
                WHEN 'ALADDIN_ID' THEN 1
                WHEN 'CLIENT_ID'  THEN 2
                WHEN 'NAME_MATCH' THEN 3
                ELSE 4
            END,
            match_score DESC,
            target_company_id
    )                     AS match_rank,
    COUNT(*) OVER (
        PARTITION BY source_system, source_company_id, target_system
    )                     AS match_count,
    match_basis,
    match_col_source,
    match_col_target,
    match_value,
    match_score
FROM all_matches
