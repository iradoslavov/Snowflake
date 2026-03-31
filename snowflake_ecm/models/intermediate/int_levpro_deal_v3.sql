{{
    config(
        database='dev_curate',
        schema='core',
        alias='deal_v3',
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['source_system', 'as_of_date'],
        tags=['levpro', 'deal']
    )
}}

WITH base AS (
    {{ ref('stg_levpro_base') }}
)

SELECT
    src.source_system,
    src.source_deal_id,
    {{ as_of_date() }}                                   AS as_of_date,
    NVL(de_ids.ecm_deal_id, UUID_STRING())               AS ecm_deal_id,
    src.source_deal_name,
    src.source_company_id,
    src.deal_other_attributes                            AS other_attributes
FROM base src
LEFT JOIN {{ source('curate_core', 'ecm_deal_ids') }} de_ids
    ON  de_ids.source_system  = src.source_system
    AND de_ids.source_deal_id = src.source_deal_id
WHERE src.rn_deal = 1
