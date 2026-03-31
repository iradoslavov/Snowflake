{{
    config(
        database='dev_curate',
        schema='core',
        alias='company_v3',
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['source_system', 'as_of_date'],
        tags=['aladdin', 'company']
    )
}}

/*
  ALADDIN slice of company_v3.
  Replaces the ALADDIN portion of the INSERT ALL → company_v3 block.

  NVL(existing_ecm_id, UUID_STRING()) preserves previously-assigned IDs
  by reading from the live ecm_company_ids registry (via source, not ref,
  to avoid a circular dependency in the DAG).
*/

WITH base AS (
    {{ ref('stg_aladdin_base') }}
)

SELECT
    src.source_system,
    src.source_company_id,
    {{ as_of_date() }}                                   AS as_of_date,
    NVL(co_ids.ecm_company_id, UUID_STRING())            AS ecm_company_id,
    src.source_company_name,
    NULL::VARIANT                                        AS other_attributes
FROM base src
LEFT JOIN {{ source('curate_core', 'ecm_company_ids') }} co_ids
    ON  co_ids.source_system     = src.source_system
    AND co_ids.source_company_id = src.source_company_id
WHERE src.rn_company = 1
