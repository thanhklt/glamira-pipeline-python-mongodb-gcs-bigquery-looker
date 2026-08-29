{{
    config(
        materialized='incremental',
        unique_key='detail_key',
        incremental_strategy='merge'
    )
}}

WITH fact_sales_order_detail__source AS (
    SELECT *
    FROM {{ref('stg_fact_sales_order_detail')}}

    {% if is_incremental() %} -- Chỉ chạy nếu là incremental
    WHERE detail_key NOT IN (
        SELECT detail_key
        FROM {{ this }}
    )
    {% endif %}
),

fact_sales_order_detail__null_handle AS (
    SELECT
        detail_key,
        COALESCE(customer_key, -1) AS customer_key,
        COALESCE(product_key, -1) AS product_key,
        COALESCE(location_key, -1) AS location_key,
        COALESCE(currency_key, -1) AS currency_key,
        COALESCE(store_key, -1) AS store_key,
        COALESCE(date_key, '1970-01-01') AS date_key,
        order_id,
        local_time,
        time_stamp,
        ip,
        sales_amount,
        sales_local_price,
        sales_usd_price
    FROM
        fact_sales_order_detail__source
),

fact_sales_order_detail__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM
        fact_sales_order_detail__null_handle
)

SELECT * FROM fact_sales_order_detail__audit

