{{
    config(materialized='ephemeral')
}}

/*
  Shared base subquery for iLEVEL company_v3, deal_v3, and security_v3 models.
  Inlined as a CTE in each downstream model, filtered on rn_company / rn_deal / rn_security.
*/

WITH vpd AS (
    SELECT DISTINCT investmentid, investment, securityid, security
    FROM {{ source('ilevel', 'view_periodic_data') }}
    WHERE securityid IS NOT NULL
),

fn_data AS (
    SELECT
        investment,
        MAX(CASE WHEN dataitem = 'Borrower Legal Name'    THEN dataitemvalue END) AS borrower_legal_name,
        MAX(CASE WHEN dataitem = 'Sponsor Name'           THEN dataitemvalue END) AS sponsor_name,
        MAX(CASE WHEN dataitem = 'Transaction Close Date' THEN dataitemvalue END) AS transaction_close_date
    FROM TABLE(dev_publish.kurtosys.fn_ilevel('%', TO_DATE('2025-12-31'), 'Borrower Legal Name,Sponsor Name,Transaction Close Date'))
    GROUP BY investment
)

SELECT
    'ILEVEL'                                                                  AS source_system,
    UPPER(TRIM(SPLIT_PART(SPLIT_PART(vpd.investment, '[', 1), '(', 1)))      AS source_company_id,
    TRIM(SPLIT_PART(SPLIT_PART(vpd.investment, '[', 1), '(', 1))             AS source_company_name,
    vpd.investmentid::VARCHAR                                                 AS source_deal_id,
    vpd.investment                                                            AS source_deal_name,
    vpd.securityid::VARCHAR                                                   AS source_security_id,
    adc.aladdin_id,
    vpd.security                                                              AS client_id,
    OBJECT_CONSTRUCT(
        'borrower_legal_name',    fn.borrower_legal_name,
        'sponsor_name',           fn.sponsor_name,
        'transaction_close_date', fn.transaction_close_date
    )                                                                         AS deal_other_attributes,
    OBJECT_CONSTRUCT(
        'sponsor_name', FIRST_VALUE(fn.sponsor_name) OVER (
            PARTITION BY UPPER(TRIM(SPLIT_PART(SPLIT_PART(vpd.investment, '[', 1), '(', 1)))
            ORDER BY fn.transaction_close_date DESC NULLS LAST
        )
    )                                                                         AS company_other_attributes,
    ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(SPLIT_PART(SPLIT_PART(vpd.investment, '[', 1), '(', 1)))
        ORDER BY vpd.investmentid
    )                                                                         AS rn_company,
    ROW_NUMBER() OVER (
        PARTITION BY vpd.investmentid
        ORDER BY vpd.securityid
    )                                                                         AS rn_deal,
    ROW_NUMBER() OVER (
        PARTITION BY vpd.securityid
        ORDER BY vpd.investmentid
    )                                                                         AS rn_security
FROM vpd
LEFT JOIN fn_data fn
    ON  fn.investment = vpd.investment
LEFT JOIN {{ ref('stg_adc_ids') }} adc
    ON  adc.identifier = vpd.security
