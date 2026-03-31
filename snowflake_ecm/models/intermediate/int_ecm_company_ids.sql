{{
    config(
        database='dev_curate',
        schema='core',
        alias='ecm_company_ids',
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['source_system', 'source_company_id'],
        merge_update_columns=['ecm_company_id'],   -- update is a no-op: keeps existing ID
        tags=['registry']
    )
}}

/*
  Persistent ECM company ID registry.
  Collects newly-minted ecm_company_ids from all four source systems.
  The MERGE only inserts new (source_system, source_company_id) pairs;
  existing rows are never updated, preserving ID stability.

  Must run AFTER all *_company_v3 models so UUIDs are already generated.
*/

SELECT DISTINCT source_system, source_company_id, ecm_company_id, {{ as_of_date() }} AS create_date
FROM {{ ref('int_aladdin_company_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_company_id, ecm_company_id, {{ as_of_date() }}
FROM {{ ref('int_ilevel_company_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_company_id, ecm_company_id, {{ as_of_date() }}
FROM {{ ref('int_levpro_company_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_company_id, ecm_company_id, {{ as_of_date() }}
FROM {{ ref('int_salesforce_company_v3') }}
WHERE as_of_date = {{ as_of_date() }}
