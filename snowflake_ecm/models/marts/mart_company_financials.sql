{{
    config(
        database='dev_publish',
        schema='public',
        alias='company_financials',
        materialized='table',
        tags=['publish', 'financials']
    )
}}

WITH ilevel_company AS (
    SELECT source_company_id AS ilevel_company_id, ecm_company_id
    FROM {{ ref('int_ilevel_company_v3') }}
    WHERE as_of_date = {{ as_of_date() }}
),

base AS (
    SELECT
        investment, investmentid, periodend, periodlength, dataitem,
        CAST(dataitemvalue AS FLOAT) AS dataitemvalue
    FROM TABLE(DEV_RAW.ILEVEL.FN_ILEVEL_MARANON_ALL_PERIODS('%', 'Adj. EBITDA,EBITDA Adjustments,Revenue%,Net Income,Total Assets'))
    WHERE "Row Type 2" = ' -> INVESTMENT -> '
      AND scenario     = 'Actual'
),

-- Roll up Revenue 1-5 into a single Revenue dataitem
base_normalized AS (
    SELECT
        investment, investmentid, periodend, periodlength,
        CASE WHEN dataitem ILIKE 'Revenue%' THEN 'Revenue' ELSE dataitem END AS dataitem,
        dataitemvalue
    FROM base
),

base_agg AS (
    SELECT investment, investmentid, periodend, periodlength, dataitem, SUM(dataitemvalue) AS dataitemvalue
    FROM base_normalized
    GROUP BY investment, investmentid, periodend, periodlength, dataitem
),

periods AS (
    SELECT DISTINCT investment, investmentid, periodend FROM base_agg
),

dataitems AS (
    SELECT DISTINCT dataitem FROM base_agg WHERE dataitem != 'Total Assets'
),

spine AS (
    SELECT p.investment, p.investmentid, p.periodend, d.dataitem
    FROM periods p CROSS JOIN dataitems d
),

-- LTM direct
ltm AS (
    SELECT investment, investmentid, periodend, dataitem, dataitemvalue AS value_ltm
    FROM base_agg
    WHERE periodlength = 'LTM' AND dataitem != 'Total Assets'
),

-- L3M: 4 most recent L3M rows on or before each spine period end
l3m_ranked AS (
    SELECT
        s.investment, s.investmentid,
        s.periodend    AS spine_periodend,
        b.dataitem, b.dataitemvalue,
        ROW_NUMBER() OVER (
            PARTITION BY s.investment, s.periodend, b.dataitem
            ORDER BY b.periodend DESC
        ) AS rn
    FROM spine s
    LEFT JOIN base_agg b
        ON  b.investment   = s.investment
        AND b.dataitem     = s.dataitem
        AND b.periodlength = 'L3M'
        AND b.periodend   <= s.periodend
),

l3m AS (
    SELECT
        investment, investmentid, spine_periodend AS periodend, dataitem,
        COUNT(dataitemvalue)                                             AS l3m_count,
        CASE WHEN COUNT(dataitemvalue) = 4 THEN SUM(dataitemvalue) END  AS value_l3m_derived
    FROM l3m_ranked WHERE rn <= 4
    GROUP BY investment, investmentid, spine_periodend, dataitem
),

-- Month: 12 most recent Month rows on or before each spine period end
mnth_ranked AS (
    SELECT
        s.investment, s.investmentid,
        s.periodend    AS spine_periodend,
        b.dataitem, b.dataitemvalue,
        ROW_NUMBER() OVER (
            PARTITION BY s.investment, s.periodend, b.dataitem
            ORDER BY b.periodend DESC
        ) AS rn
    FROM spine s
    LEFT JOIN base_agg b
        ON  b.investment   = s.investment
        AND b.dataitem     = s.dataitem
        AND b.periodlength = 'Month'
        AND b.periodend   <= s.periodend
),

mnth AS (
    SELECT
        investment, investmentid, spine_periodend AS periodend, dataitem,
        COUNT(dataitemvalue)                                              AS month_count,
        CASE WHEN COUNT(dataitemvalue) = 12 THEN SUM(dataitemvalue) END  AS value_month_derived
    FROM mnth_ranked WHERE rn <= 12
    GROUP BY investment, investmentid, spine_periodend, dataitem
),

-- Total Assets: most recent on or before each spine period end
total_assets_ranked AS (
    SELECT
        p.investment, p.investmentid,
        p.periodend  AS spine_periodend,
        b.periodend  AS ta_periodend,
        b.dataitemvalue,
        ROW_NUMBER() OVER (
            PARTITION BY p.investment, p.investmentid, p.periodend
            ORDER BY b.periodend DESC
        ) AS rn
    FROM periods p
    LEFT JOIN base_agg b
        ON  b.investment   = p.investment
        AND b.investmentid = p.investmentid
        AND b.dataitem     = 'Total Assets'
        AND b.periodend   <= p.periodend
),

total_assets AS (
    SELECT investment, investmentid, spine_periodend AS periodend,
           dataitemvalue AS total_assets_value, ta_periodend AS total_assets_as_of
    FROM total_assets_ranked WHERE rn = 1
),

-- Waterfall: LTM → L3M×4 → Month×12
combined AS (
    SELECT
        s.investment, s.investmentid, s.periodend, s.dataitem,
        ltm.value_ltm,
        l3m.value_l3m_derived,
        mnth.value_month_derived,
        COALESCE(ltm.value_ltm, l3m.value_l3m_derived, mnth.value_month_derived) AS value_waterfall,
        CASE WHEN ltm.value_ltm            IS NOT NULL THEN 'LTM'
             WHEN l3m.value_l3m_derived    IS NOT NULL THEN 'L3M x4'
             WHEN mnth.value_month_derived IS NOT NULL THEN 'Month x12'
             ELSE NULL
        END AS waterfall_source
    FROM spine s
    LEFT JOIN ltm  ON ltm.investment  = s.investment  AND ltm.periodend  = s.periodend  AND ltm.dataitem  = s.dataitem
    LEFT JOIN l3m  ON l3m.investment  = s.investment  AND l3m.periodend  = s.periodend  AND l3m.dataitem  = s.dataitem
    LEFT JOIN mnth ON mnth.investment = s.investment  AND mnth.periodend = s.periodend  AND mnth.dataitem = s.dataitem
),

financials AS (
    SELECT
        c.investment, c.investmentid, c.periodend,
        MAX(CASE WHEN c.dataitem = 'Adj. EBITDA'        THEN c.value_waterfall  END) AS adj_ebitda,
        MAX(CASE WHEN c.dataitem = 'Adj. EBITDA'        THEN c.waterfall_source END) AS adj_ebitda_source,
        MAX(CASE WHEN c.dataitem = 'EBITDA Adjustments' THEN c.value_waterfall  END) AS ebitda_adjustments,
        MAX(CASE WHEN c.dataitem = 'EBITDA Adjustments' THEN c.waterfall_source END) AS ebitda_adjustments_source,
        MAX(CASE WHEN c.dataitem = 'Revenue'            THEN c.value_waterfall  END) AS revenue,
        MAX(CASE WHEN c.dataitem = 'Revenue'            THEN c.waterfall_source END) AS revenue_source,
        MAX(CASE WHEN c.dataitem = 'Net Income'         THEN c.value_waterfall  END) AS net_income,
        MAX(CASE WHEN c.dataitem = 'Net Income'         THEN c.waterfall_source END) AS net_income_source,
        MAX(ta.total_assets_value)                                                   AS total_assets,
        MAX(ta.total_assets_as_of)                                                   AS total_assets_as_of
    FROM combined c
    LEFT JOIN total_assets ta
        ON  ta.investment   = c.investment
        AND ta.investmentid = c.investmentid
        AND ta.periodend    = c.periodend
    WHERE c.periodend > DATEADD('year', -1, CURRENT_DATE())
    GROUP BY c.investment, c.investmentid, c.periodend
)

SELECT
    co.ecm_company_id,
    TO_DATE(f.periodend)       AS period_end,
    f.adj_ebitda,
    f.adj_ebitda_source,
    f.ebitda_adjustments,
    f.ebitda_adjustments_source,
    f.revenue,
    f.revenue_source,
    f.net_income,
    f.net_income_source,
    f.total_assets,
    f.total_assets_as_of
FROM financials f
JOIN ilevel_company co
    ON  co.ilevel_company_id = UPPER(TRIM(SPLIT_PART(SPLIT_PART(f.investment, '[', 1), '(', 1)))
ORDER BY f.investment, f.periodend DESC
