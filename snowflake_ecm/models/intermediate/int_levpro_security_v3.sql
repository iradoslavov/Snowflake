{{
    config(
        database='dev_curate',
        schema='core',
        alias='security_v3',
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['source_system', 'as_of_date'],
        tags=['levpro', 'security']
    )
}}

WITH base AS (
    {{ ref('stg_levpro_base') }}
)

SELECT
    src.source_system,
    src.source_security_id,
    {{ as_of_date() }}                                   AS as_of_date,
    NVL(se_ids.ecm_security_id, UUID_STRING())           AS ecm_security_id,
    src.aladdin_id,
    src.client_id,
    NULL::VARCHAR                                        AS source_issuer_id,
    src.source_company_id,
    NULL::VARIANT                                        AS other_attributes
FROM base src
LEFT JOIN {{ source('curate_core', 'ecm_security_ids') }} se_ids
    ON  se_ids.source_system      = src.source_system
    AND se_ids.source_security_id = src.source_security_id
WHERE src.rn_security = 1
