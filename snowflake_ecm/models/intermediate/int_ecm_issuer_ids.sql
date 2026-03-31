{{
    config(
        database='dev_curate',
        schema='core',
        alias='ecm_issuer_ids',
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['source_system', 'source_issuer_id'],
        merge_update_columns=['ecm_issuer_id'],
        tags=['registry']
    )
}}

SELECT DISTINCT source_system, source_issuer_id, ecm_issuer_id, {{ as_of_date() }} AS create_date
FROM {{ ref('int_aladdin_issuer_v3') }}
WHERE as_of_date = {{ as_of_date() }}
