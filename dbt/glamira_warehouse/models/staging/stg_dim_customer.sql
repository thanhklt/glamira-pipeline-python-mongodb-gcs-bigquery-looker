WITH stg_dim_customer__source AS (
    SELECT *
    FROM {{source('landing','raw_mongo')}}
),

stg_dim_customer__get_col AS (
    SELECT
        device_id,
        user_agent,
        user_id_db,
        email_address
    FROM stg_dim_customer__source
),

stg_dim_customer__rename AS (
    SELECT
        device_id as customer_device_id,
        user_agent as customer_user_agent,
        user_id_db as customer_user_id_db,
        email_address as customer_email_address
    FROM stg_dim_customer__get_col
),

stg_dim_customer__trim AS (
    SELECT
        trim(customer_device_id) as customer_device_id,
        trim(customer_user_agent) as customer_user_agent,
        trim(customer_user_id_db) as customer_user_id_db,
        trim(customer_email_address) as customer_email_address
    FROM stg_dim_customer__rename
),

stg_dim_customer__dedupe AS (
    SELECT DISTINCT *
    FROM stg_dim_customer__trim
),

stg_dim_customer__scd AS (
    SELECT
        *,
        current_date('Asia/Ho_Chi_Minh') as start_date,
        '9999-1-1' AS end_date,
        true AS is_current
    FROM stg_dim_customer__dedupe
),

stg_dim_customer__genkey AS (
    SELECT
        farm_fingerprint(
            concat(
                customer_device_id,
                '|',
                customer_user_agent,
                '|',
                customer_user_id_db,
                '|',
                customer_email_address
            )
        ) as customer_key,
        *
    FROM stg_dim_customer__scd
)

SELECT * FROM stg_dim_customer__genkey
