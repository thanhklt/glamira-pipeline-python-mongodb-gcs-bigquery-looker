WITH dim_customer__source AS (
    SELECT *
    FROM {{ ref('stg_dim_customer') }}
),

dim_customer__null_handle AS (
    SELECT
        customer_key,
        COALESCE(customer_device_id, 'XNA') AS customer_device_id,
        COALESCE(customer_user_agent, 'XNA') AS customer_user_agent,
        COALESCE(customer_user_id_db, 'XNA') AS customer_user_id_db,
        COALESCE(customer_email_address, 'XNA') AS customer_email_address,
        COALESCE(start_time, TIMESTAMP '1900-01-01 00:00:00+00') AS start_time,
        COALESCE(end_time, TIMESTAMP '9999-01-01 00:00:00+00') AS end_time,
        COALESCE(is_current, FALSE) AS is_current
    FROM dim_customer__source
),

dim_customer__special_row AS (
    SELECT * FROM dim_customer__null_handle
    UNION ALL
    SELECT
        -1, 
        'XNA' AS customer_device_id, 
        'XNA' AS customer_user_agent, 
        'XNA' AS customer_user_id_db, 
        'XNA' AS customer_email_address,
        TIMESTAMP '1900-01-01 00:00:00+00' AS start_time,
        TIMESTAMP '9999-01-01 00:00:00+00' AS end_time,
        FALSE  AS is_current
),

dim_customer__audit AS (
    SELECT
        customer_key,
        customer_device_id,
        customer_user_agent,
        customer_user_id_db,
        customer_email_address,
        start_time,
        end_time,
        is_current,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_customer__special_row
)

SELECT * FROM dim_customer__audit
