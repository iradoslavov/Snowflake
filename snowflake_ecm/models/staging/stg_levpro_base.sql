{{
    config(materialized='ephemeral')
}}

/*
  Shared base subquery for LEVPRO company_v3, deal_v3, and security_v3 models.
*/

WITH funded AS (
    SELECT DISTINCT ref_issuer_group, ref_name, sec_id, sec_loanx_id
    FROM {{ source('levpro', 'vw_latest_funded_positions') }}
    WHERE ref_issuer_group IS NOT NULL
      AND sec_id           IS NOT NULL
),

deals AS (
    SELECT deal_id, sec_deal_name, ref_name, ref_issuer_group, pricing_date, sec_id
    FROM {{ source('levpro', 'vw_latest_primary_deals_old') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sec_id
        ORDER BY pricing_date DESC NULLS LAST
    ) = 1
)

SELECT
    'LEVPRO'                                                   AS source_system,
    UPPER(TRIM(h.ref_issuer_group))                            AS source_company_id,
    h.ref_issuer_group                                         AS source_company_name,
    COALESCE(
        NULLIF(d.deal_id::VARCHAR, ''),
        UPPER(TRIM(h.ref_issuer_group))
    )                                                          AS source_deal_id,
    COALESCE(d.sec_deal_name, h.ref_issuer_group)              AS source_deal_name,
    h.sec_id::VARCHAR                                          AS source_security_id,
    adc.aladdin_id,
    h.sec_loanx_id                                             AS client_id,
    OBJECT_CONSTRUCT(
        'issuer_name', d.ref_name
    )                                                          AS deal_other_attributes,
    OBJECT_CONSTRUCT(
        'sponsor_name', NULL::VARCHAR
    )                                                          AS company_other_attributes,
    ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(h.ref_issuer_group))
        ORDER BY h.sec_id
    )                                                          AS rn_company,
    ROW_NUMBER() OVER (
        PARTITION BY COALESCE(NULLIF(d.deal_id::VARCHAR, ''), UPPER(TRIM(h.ref_issuer_group)))
        ORDER BY h.sec_id
    )                                                          AS rn_deal,
    ROW_NUMBER() OVER (
        PARTITION BY h.sec_id
        ORDER BY 1
    )                                                          AS rn_security
FROM funded h
LEFT JOIN deals d
    ON  d.sec_id = h.sec_id
LEFT JOIN {{ ref('stg_adc_ids') }} adc
    ON  adc.identifier = h.sec_loanx_id
