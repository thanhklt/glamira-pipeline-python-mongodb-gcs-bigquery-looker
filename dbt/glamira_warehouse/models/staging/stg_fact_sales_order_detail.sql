WITH stg_fact_sales_order_detail__source AS (
    SELECT *
    FROM {{ source('landing', 'raw_mongo') }}
),

stg_fact_sales_order_detail__filter AS (
    SELECT 
        order_id,
        device_id,
        user_agent,
        user_id_db,
        email_address,
        store_id,
        current_url,
        {{ parse_epoch_seconds('time_stamp') }} AS time_stamp,
        ip,
        cart_products
    FROM 
        stg_fact_sales_order_detail__source
    WHERE 
        collection = 'checkout_success'
),

stg_fact_sales_order_detail__cast_type AS (
    SELECT
        CAST(order_id AS STRING) AS order_id,
        CAST(device_id AS STRING) AS device_id,
        CAST(user_agent AS STRING) AS user_agent,
        CAST(user_id_db AS STRING) AS user_id_db,
        CAST(email_address AS STRING) AS email_address,
        CAST(store_id AS STRING) AS store_id,
        CAST(current_url AS STRING) AS current_url,
        time_stamp,
        CAST(ip AS STRING) AS ip,
        cart_products
    FROM
        stg_fact_sales_order_detail__filter
)

SELECT * FROM stg_fact_sales_order_detail__cast_type
