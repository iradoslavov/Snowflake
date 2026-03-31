{{
    config(
        database='dev_publish',
        schema='public',
        alias='pos_analytics_latest',
        materialized='table',
        tags=['publish', 'positions']
    )
}}

/*
  Latest 2-business-day position snapshot for ELD_ALL portfolio group.
  The target_date CTE computes the prior business day relative to as_of_date,
  accounting for Monday (back 4 days) and Tuesday (back 5 days to avoid weekend).
*/

WITH target_date AS (
    SELECT
        CASE
            WHEN DAYOFWEEK({{ as_of_date() }}) = 1 THEN DATEADD(DAY, -4, {{ as_of_date() }})
            WHEN DAYOFWEEK({{ as_of_date() }}) = 2 THEN DATEADD(DAY, -5, {{ as_of_date() }})
            ELSE                                        DATEADD(DAY, -2, {{ as_of_date() }})
        END AS pos_date
),

eld_funds AS (
    SELECT DISTINCT fund
    FROM {{ source('aladdin_share', 'port_group') }}
    WHERE portfolio_group_name = 'ELD_ALL'
)

SELECT
    td.pos_date                AS as_of_date,
    p.aladdin_id,
    p.fund::VARCHAR            AS fund,
    p.portfolio_name,
    p.strategy_name,
    p.mkt_value_usd,
    p.cur_face,
    p.market_price
FROM eld_funds ef
JOIN {{ source('aladdin_share', 'pos_analytics') }} p
    ON  p.fund = ef.fund
JOIN target_date td
    ON  p.pos_date = td.pos_date
