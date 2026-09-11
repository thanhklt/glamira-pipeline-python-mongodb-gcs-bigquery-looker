{{
    config(
        materialized='incremental',
        unique_key=['order_id', 'product_key', 'time_stamp'],
        incremental_strategy='merge'
    )
}}

WITH int_fact_sales_order_detail_normalize AS (
    SELECT *
    FROM {{ ref('int_fact_sales_order_detail_normalize') }}
),

currency_mapping AS (
    SELECT *
    FROM {{ ref('currency_mapping') }}
),

fact_exchange_rate AS (
    SELECT *
    FROM {{ ref('fact_exchange_rate') }}
),

dim_currency AS (
    SELECT *
    FROM {{ ref('dim_currency') }}
),

dim_customer AS (
    SELECT *
    FROM {{ ref('dim_customer') }}
),

dim_date AS (
    SELECT *
    FROM {{ ref('dim_date') }}
),

dim_location AS (
    SELECT *
    FROM {{ ref('dim_location') }}
),

dim_product AS (
    SELECT *
    FROM {{ ref('dim_product') }}
),

dim_store AS (
    SELECT *
    FROM {{ ref('dim_store') }}
),

-- 1. Lookup location_key tu dim_location
fact_sales_order_detail__joined__location AS (
    SELECT
        int_fact_sales_order_detail_normalize.*,
        dim.location_key
    FROM 
        int_fact_sales_order_detail_normalize
    LEFT JOIN
        dim_location AS dim
        ON
            dim.location_city_name = int_fact_sales_order_detail_normalize.location_city_name AND
            dim.location_region_name = int_fact_sales_order_detail_normalize.location_region_name AND
            dim.location_country_code = int_fact_sales_order_detail_normalize.location_country_code AND
            dim.location_country_name = int_fact_sales_order_detail_normalize.location_country_name
),

-- 2. Lookup customer_key tu dim_customer (SCD Type 2)
fact_sales_order_detail__joined__customer AS (
    SELECT
        current_fact.*,
        dim_customer.customer_key
    FROM
        fact_sales_order_detail__joined__location AS current_fact
    LEFT JOIN
        dim_customer
        ON
            NULLIF(TRIM(CAST(current_fact.device_id AS STRING)), '')
                = dim_customer.customer_device_id
            AND current_fact.time_stamp >= dim_customer.start_time
            AND current_fact.time_stamp < dim_customer.end_time
),

-- 3. Lookup product_key tu dim_product
fact_sales_order_detail__joined__product AS (
    SELECT
        current_fact.*,
        dim_product.product_key
    FROM
        fact_sales_order_detail__joined__customer AS current_fact
    LEFT JOIN
        dim_product
        ON CAST(current_fact.product_id AS STRING) = dim_product.product_id
),

-- 4. Lookup currency_key tu dim_currency qua currency_mapping
fact_sales_order_detail__joined__currency AS (
    SELECT
        current_fact.*,
        dim_currency.currency_key
    FROM
        fact_sales_order_detail__joined__product AS current_fact
    LEFT JOIN
        currency_mapping AS mapping
        ON TRIM(current_fact.raw_currency) = mapping.raw_currency
    LEFT JOIN
        dim_currency
        ON mapping.currency_code = dim_currency.currency_code
),

-- 5. Lookup store_key tu dim_store
fact_sales_order_detail__joined__store AS (
    SELECT
        current_fact.*,
        dim_store.store_key
    FROM
        fact_sales_order_detail__joined__currency AS current_fact
    LEFT JOIN
        dim_store
        ON
            current_fact.store_id = dim_store.store_id AND
            current_fact.store_domain = dim_store.store_domain
),

-- 6. Lookup date_key tu dim_date
fact_sales_order_detail__joined__date AS (
    SELECT
        current_fact.*,
        dim_date.date_key
    FROM
        fact_sales_order_detail__joined__store AS current_fact
    LEFT JOIN
        dim_date
        ON DATE(current_fact.time_stamp) = dim_date.date_key
),

fact_sales_order_detail__dedupe_cart AS (
    SELECT
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        time_stamp,
        ip,
        SUM(CAST(amount AS INT64)) AS sales_amount,
        AVG(CAST(price AS NUMERIC)) AS sales_local_price
    FROM
        fact_sales_order_detail__joined__date
    GROUP BY
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        time_stamp,
        ip
),

-- 7. Quy doi gia tri sang USD tu fact_exchange_rate
fact_sales_order_detail__get_usd_price AS (
    SELECT
        sales.customer_key,
        sales.product_key,
        sales.location_key,
        sales.currency_key,
        sales.store_key,
        sales.order_id,
        sales.date_key,
        sales.time_stamp,
        sales.ip,
        sales_amount,
        sales_local_price,
        ROUND(
            sales.sales_local_price * exchange_rate.rate_to_usd,
            2
        ) AS sales_usd_price
    FROM
        fact_sales_order_detail__dedupe_cart AS sales
    LEFT JOIN
        fact_exchange_rate AS exchange_rate
        ON 
            sales.currency_key = exchange_rate.currency_key AND
            sales.date_key = exchange_rate.date_key
),

-- 8. Xu ly gia tri NULL cho cac khoa thay the
fact_sales_order_detail__null_handle AS (
    SELECT
        COALESCE(customer_key, -1) AS customer_key,
        COALESCE(product_key, -1) AS product_key,
        COALESCE(location_key, -1) AS location_key,
        COALESCE(currency_key, -1) AS currency_key,
        COALESCE(store_key, -1) AS store_key,
        COALESCE(date_key, '1970-01-01') AS date_key,
        order_id,
        time_stamp, 
        ip,
        sales_amount,
        sales_local_price,
        sales_usd_price
    FROM
        fact_sales_order_detail__get_usd_price
),

-- 9. Ep kieu du lieu chuan
fact_sales_order_detail__cast_type AS (
    SELECT
        CAST(customer_key AS INT64) AS customer_key,
        CAST(product_key AS INT64) AS product_key,
        CAST(location_key AS INT64) AS location_key,
        CAST(currency_key AS INT64) AS currency_key,
        CAST(store_key AS INT64) AS store_key,
        CAST(date_key AS DATE) AS date_key,
        CAST(order_id AS STRING) AS order_id,
        CAST(time_stamp AS TIMESTAMP) AS time_stamp,
        CAST(ip AS STRING) AS ip,
        CAST(sales_amount AS INT64) AS sales_amount,
        CAST(sales_local_price AS NUMERIC) AS sales_local_price,
        CAST(sales_usd_price AS NUMERIC) AS sales_usd_price
    FROM
        fact_sales_order_detail__null_handle
),

-- 10. Tao surrogate key cho bang Fact
fact_sales_order_detail__genkey AS (
    SELECT
        FARM_FINGERPRINT(
            CONCAT(
                order_id, '|',
                CAST(product_key AS STRING), '|',
                CAST(time_stamp AS STRING)
            )
        ) AS detail_key,
        *
    FROM fact_sales_order_detail__cast_type
),

-- 11. Xu ly Incremental Merge
fact_sales_order_detail__incremental AS (
    SELECT *
    FROM fact_sales_order_detail__genkey
    {% if is_incremental() %}
    WHERE detail_key NOT IN (
        SELECT detail_key
        FROM {{ this }}
    )
    {% endif %}
),

-- 12. Gan metadata audit
fact_sales_order_detail__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM
        fact_sales_order_detail__incremental
)

SELECT * FROM fact_sales_order_detail__audit
