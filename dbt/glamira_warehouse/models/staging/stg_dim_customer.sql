WITH stg_dim_customer__source AS (
    SELECT
        NULLIF(TRIM(CAST(device_id AS STRING)), '') AS customer_device_id,
        NULLIF(TRIM(CAST(user_agent AS STRING)), '') AS customer_user_agent,
        NULLIF(TRIM(CAST(user_id_db AS STRING)), '') AS customer_user_id_db,
        NULLIF(TRIM(CAST(email_address AS STRING)), '') AS customer_email_address,
        {{ parse_epoch_seconds('time_stamp') }} AS record_time
    FROM {{ source('landing', 'raw_mongo') }}
),

stg_dim_customer__valid AS (
    SELECT * EXCEPT(rn)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY customer_device_id, record_time
                ORDER BY
                    (customer_email_address IS NOT NULL) DESC,
                    (customer_user_id_db IS NOT NULL) DESC,
                    (customer_user_agent IS NOT NULL) DESC
            ) AS rn
        FROM stg_dim_customer__source
        WHERE customer_device_id IS NOT NULL
          AND record_time IS NOT NULL
    )
    WHERE rn = 1
),
stg_dim_customer__previous_state AS (
    SELECT
        *,
        ROW_NUMBER() OVER customer_history AS customer_version_number,
        LAG(customer_user_agent) OVER customer_history AS previous_user_agent,
        LAG(customer_user_id_db) OVER customer_history AS previous_user_id_db,
        LAG(customer_email_address) OVER customer_history AS previous_email_address
    FROM stg_dim_customer__valid
    WINDOW customer_history AS (
        PARTITION BY customer_device_id
        ORDER BY record_time
    )
),

stg_dim_customer__changes AS (
    SELECT
        customer_device_id,
        customer_user_agent,
        customer_user_id_db,
        customer_email_address,
        record_time AS start_time
    FROM stg_dim_customer__previous_state
    WHERE customer_version_number = 1
       OR customer_user_agent IS DISTINCT FROM previous_user_agent
       OR customer_user_id_db IS DISTINCT FROM previous_user_id_db
       OR customer_email_address IS DISTINCT FROM previous_email_address
),

stg_dim_customer__unique_changes AS (
    SELECT * EXCEPT(rn)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY customer_device_id, start_time
                ORDER BY
                    (customer_email_address IS NOT NULL) DESC,
                    (customer_user_id_db IS NOT NULL) DESC,
                    (customer_user_agent IS NOT NULL) DESC
            ) AS rn
        FROM stg_dim_customer__changes
    )
    WHERE rn = 1
),

stg_dim_customer__intervals AS (
    SELECT
        *,
        LEAD(start_time) OVER (
            PARTITION BY customer_device_id
            ORDER BY start_time
        ) AS next_start_time
    FROM stg_dim_customer__unique_changes
),

stg_dim_customer__scd AS (
    SELECT
        FARM_FINGERPRINT(
            CONCAT(
                customer_device_id,
                '|',
                FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%E6SZ', start_time, 'UTC')
            )
        ) AS customer_key,
        customer_device_id,
        customer_user_agent,
        customer_user_id_db,
        customer_email_address,
        start_time,
        COALESCE(
            next_start_time,
            TIMESTAMP '9999-01-01 00:00:00+00'
        ) AS end_time,
        next_start_time IS NULL AS is_current
    FROM stg_dim_customer__intervals
)

SELECT *
FROM stg_dim_customer__scd
