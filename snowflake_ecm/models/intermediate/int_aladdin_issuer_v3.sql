{{
    config(
        database='dev_curate',
        schema='core',
        alias='issuer_v3',
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['source_system', 'as_of_date'],
        tags=['aladdin', 'issuer']
    )
}}

WITH base AS (
    {{ ref('stg_aladdin_base') }}
)

SELECT
    src.source_system,
    src.source_issuer_id,
    {{ as_of_date() }}                                   AS as_of_date,
    NVL(is_ids.ecm_issuer_id, UUID_STRING())             AS ecm_issuer_id,
    src.source_issuer_name,
    src.source_company_id,
    NULL::VARIANT                                        AS other_attributes
FROM base src
LEFT JOIN {{ source('curate_core', 'ecm_issuer_ids') }} is_ids
    ON  is_ids.source_system    = src.source_system
    AND is_ids.source_issuer_id = src.source_issuer_id
WHERE src.rn_issuer = 1
