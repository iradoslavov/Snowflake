{{
    config(
        database='dev_curate',
        schema='core',
        alias='ecm_security_ids',
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['source_system', 'source_security_id'],
        merge_update_columns=['ecm_security_id'],
        tags=['registry']
    )
}}

SELECT DISTINCT source_system, source_security_id, ecm_security_id, {{ as_of_date() }} AS create_date
FROM {{ ref('int_aladdin_security_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_security_id, ecm_security_id, {{ as_of_date() }}
FROM {{ ref('int_ilevel_security_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_security_id, ecm_security_id, {{ as_of_date() }}
FROM {{ ref('int_levpro_security_v3') }}
WHERE as_of_date = {{ as_of_date() }}
