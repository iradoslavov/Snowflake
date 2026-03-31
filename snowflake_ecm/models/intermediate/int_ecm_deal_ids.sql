{{
    config(
        database='dev_curate',
        schema='core',
        alias='ecm_deal_ids',
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['source_system', 'source_deal_id'],
        merge_update_columns=['ecm_deal_id'],
        tags=['registry']
    )
}}

SELECT DISTINCT source_system, source_deal_id, ecm_deal_id, {{ as_of_date() }} AS create_date
FROM {{ ref('int_ilevel_deal_v3') }}
WHERE as_of_date = {{ as_of_date() }}

UNION ALL

SELECT DISTINCT source_system, source_deal_id, ecm_deal_id, {{ as_of_date() }}
FROM {{ ref('int_levpro_deal_v3') }}
WHERE as_of_date = {{ as_of_date() }}
