WITH customer_source AS (
    SELECT
        NULLIF(TRIM(CAST(device_id AS STRING)), '') AS customer_device_id,
        {{ parse_epoch_seconds('time_stamp') }} AS record_time
    FROM {{ source('landing', 'raw_mongo') }}
),

duplicates AS (
    SELECT
        customer_device_id,
        record_time,
        COUNT(*) AS record_count
    FROM customer_source
    WHERE customer_device_id IS NOT NULL
      AND record_time IS NOT NULL
    GROUP BY customer_device_id, record_time
    HAVING COUNT(*) > 1
)

SELECT *
FROM duplicates
