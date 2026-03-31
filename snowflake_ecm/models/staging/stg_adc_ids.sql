{{
    config(materialized='ephemeral')
}}

/*
  Bridge table: maps external client identifiers → Aladdin IDs.
  Replaces the TEMPORARY TABLE tmp_adc_ids in the original script.
  Kept ephemeral so it is inlined as a CTE wherever referenced.
*/

WITH private_ids AS (
    SELECT identifier, aladdin_id, system_start_time
    FROM {{ source('aladdin_share', 'security_private_ids') }}
    WHERE purpose IN ('ELD')
      AND system_end_time > {{ as_of_date() }}
),

public_ids AS (
    SELECT identifier, aladdin_id, system_start_time
    FROM {{ source('aladdin_share', 'security_public_ids') }}
    WHERE id_type = 'LoanX ID'
      AND system_end_time > {{ as_of_date() }}
),

combined AS (
    SELECT identifier, aladdin_id, system_start_time FROM private_ids
    UNION ALL
    SELECT identifier, aladdin_id, system_start_time FROM public_ids
)

SELECT identifier, aladdin_id
FROM combined
QUALIFY ROW_NUMBER() OVER (PARTITION BY identifier ORDER BY system_start_time DESC) = 1
