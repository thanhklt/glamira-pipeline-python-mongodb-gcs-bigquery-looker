SELECT
    device_id,
    time_stamp
FROM {{ source('landing', 'raw_mongo') }}
WHERE NULLIF(TRIM(CAST(device_id AS STRING)), '') IS NOT NULL
  AND {{ parse_epoch_seconds('time_stamp') }} IS NULL
