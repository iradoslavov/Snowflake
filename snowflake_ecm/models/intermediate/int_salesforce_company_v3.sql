{{
    config(
        database='dev_curate',
        schema='core',
        alias='company_v3',
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['source_system', 'as_of_date'],
        tags=['salesforce', 'company']
    )
}}

WITH sf AS (
    {{ ref('stg_salesforce_company') }}
)

SELECT
    sf.source_system,
    sf.source_company_id,
    {{ as_of_date() }}                                   AS as_of_date,
    NVL(co_ids.ecm_company_id, UUID_STRING())            AS ecm_company_id,
    sf.source_company_name,
    sf.other_attributes
FROM sf
LEFT JOIN {{ source('curate_core', 'ecm_company_ids') }} co_ids
    ON  co_ids.source_system     = sf.source_system
    AND co_ids.source_company_id = sf.source_company_id
