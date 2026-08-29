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
        COALESCE(start_date, DATE '1900-01-01') AS start_date,
        COALESCE(SAFE_CAST(end_date AS DATE), DATE '9999-01-01') AS end_date,
        COALESCE(is_current, FALSE) AS is_current
    FROM dim_customer__source
),

dim_customer__special_row AS (
    SELECT * FROM dim_customer__null_handle
    UNION ALL
    SELECT
        -1, 'XNA', 'XNA', 'XNA', 'XNA',
        DATE '1900-01-01', DATE '9999-01-01', FALSE
),

dim_customer__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_customer__special_row
)

SELECT * FROM dim_customer__audit
