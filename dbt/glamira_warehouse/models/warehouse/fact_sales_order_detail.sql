{{
    config(
        materialized='incremental',
        unique_key='detail_key',
        incremental_strategy='merge'
    )
}}

WITH fact_sales_order_detail__raw_mongo_source AS (
    SELECT *
    FROM {{ source('landing', 'raw_mongo') }}
),

fact_sales_order_detail__filter AS (
    SELECT *
    FROM fact_sales_order_detail__raw_mongo_source
    WHERE collection = 'checkout_success'
),

fact_sales_order_detail__raw_location_source AS (
    SELECT *
    FROM {{ source('landing', 'raw_location') }}
),

fact_sales_order_detail__raw_location_dedupe AS (
    SELECT DISTINCT
        ip,
        city_name,
        region_name,
        country_code,
        country_name
    FROM fact_sales_order_detail__raw_location_source
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

-- Lay cac cot tu raw_mongo va unnest cart_products
fact_sales_order_detail__retrieve AS (
    SELECT
        source.order_id,
        source.device_id,
        source.user_agent,
        source.user_id_db,
        source.email_address,
        source.store_id,
        source.current_url,
        source.local_time,
        source.time_stamp,
        {{ parse_epoch_seconds('source.time_stamp') }} AS record_time,
        source.ip,
        cart_product.product_id,
        cart_product.currency AS raw_currency,
        cart_product.amount AS amount,
        cart_product.price AS price
    FROM
        fact_sales_order_detail__filter AS source
    LEFT JOIN
        UNNEST(source.cart_products) AS cart_product ON TRUE
),

-- Lay location_key tu dim_location
fact_sales_order_detail__joined__location AS (
    SELECT
        current_fact.*,
        dim.location_key
    FROM 
        fact_sales_order_detail__retrieve AS current_fact
    LEFT JOIN
        fact_sales_order_detail__raw_location_dedupe AS source
        ON
            current_fact.ip = source.ip
    LEFT JOIN
        dim_location AS dim
        ON
            dim.location_city_name = source.city_name AND
            dim.location_region_name = source.region_name AND
            dim.location_country_code = source.country_code AND
            dim.location_country_name = source.country_name
),

-- Lay customer_key tu dim_customer (lookup tren bang chieu vat ly)
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
            AND current_fact.record_time >= dim_customer.start_time
            AND current_fact.record_time < dim_customer.end_time
),

-- Lay product_key tu dim_product
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

-- Lay currency_key tu dim_currency
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

-- Lay store_key tu dim_store
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
            regexp_extract(
                lower(regexp_extract(current_fact.current_url, r'^https?://([^/:]+)')),
                r'(\.[^.]+)$'
            ) = dim_store.store_domain
),

-- Lay date_key tu dim_date
fact_sales_order_detail__joined__date AS (
    SELECT
        current_fact.*,
        dim_date.date_key
    FROM
        fact_sales_order_detail__joined__store AS current_fact
    LEFT JOIN
        dim_date
        ON CAST(CAST(current_fact.local_time AS DATETIME) AS DATE) = dim_date.date_key
),

fact_sales_order_detail__measurement AS (
    SELECT
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        local_time,
        time_stamp,
        ip,
        amount,
        price
    FROM fact_sales_order_detail__joined__date
),

fact_sales_order_detail__normalize_price AS (
    SELECT
        * EXCEPT(price),
        SAFE_CAST(
            CASE
                -- European format: 2.962,00 or 1.234.567,89
                WHEN REGEXP_CONTAINS(price, r'^\d{1,3}(\.\d{3})+,\d+$')
                    THEN REPLACE(REPLACE(price, '.', ''), ',', '.')

                -- US format: 1,094.00 or 1,234,567.89
                WHEN REGEXP_CONTAINS(price, r'^\d{1,3}(,\d{3})+\.\d+$')
                    THEN REPLACE(price, ',', '')

                -- Decimal comma without a thousands separator: 10,00
                WHEN REGEXP_CONTAINS(price, r'^\d+,\d+$')
                    THEN REPLACE(price, ',', '.')

                ELSE price
            END AS NUMERIC
        ) AS price
    FROM fact_sales_order_detail__measurement
),

fact_sales_order_detail__aggregate_cart AS (
    SELECT
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        local_time,
        time_stamp,
        ip,
        AVG(CAST(price AS NUMERIC)) AS price,
        SUM(SAFE_CAST(amount AS INT64)) AS amount
    FROM
        fact_sales_order_detail__normalize_price
    GROUP BY
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        local_time,
        time_stamp,
        ip
),

fact_sales_order_detail__get_usd_price AS (
    SELECT
        facts.customer_key,
        facts.product_key,
        facts.location_key,
        facts.currency_key,
        facts.store_key,
        facts.order_id,
        facts.date_key,
        facts.local_time,
        facts.time_stamp,
        facts.ip,
        facts.amount,
        facts.price,
        ROUND(
            facts.price * fx.rate_to_usd,
            2
        ) AS sales_usd_price
    FROM
        fact_sales_order_detail__aggregate_cart AS facts
    LEFT JOIN
        fact_exchange_rate AS fx
        ON 
            facts.currency_key = fx.currency_key AND
            facts.date_key = fx.date_key
),

fact_sales_order_detail__rename AS (
    SELECT
        customer_key,
        product_key,
        location_key,
        currency_key,
        store_key,
        order_id,
        date_key,
        local_time,
        time_stamp,
        ip,
        amount AS sales_amount,
        price AS sales_local_price,
        sales_usd_price
    FROM fact_sales_order_detail__get_usd_price
),

fact_sales_order_detail__null_handle AS (
    SELECT
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
        fact_sales_order_detail__rename
),

fact_sales_order_detail__cast_type AS (
    SELECT
        CAST(customer_key AS INT64) AS customer_key,
        CAST(product_key AS INT64) AS product_key,
        CAST(location_key AS INT64) AS location_key,
        CAST(currency_key AS INT64) AS currency_key,
        CAST(store_key AS INT64) AS store_key,
        CAST(date_key AS DATE) AS date_key,
        CAST(order_id AS STRING) AS order_id,
        CAST(local_time AS STRING) AS local_time,
        {{ parse_epoch_seconds('time_stamp') }} AS time_stamp,
        CAST(ip AS STRING) AS ip,
        CAST(sales_amount AS INT64) AS sales_amount,
        CAST(sales_local_price AS NUMERIC) AS sales_local_price,
        CAST(sales_usd_price AS NUMERIC) AS sales_usd_price
    FROM
        fact_sales_order_detail__null_handle
),

fact_sales_order_detail__genkey AS (
    SELECT
        FARM_FINGERPRINT(
            CONCAT(
                order_id, '|',
                product_key, '|',
                time_stamp
            )
        ) AS detail_key,
        *
    FROM fact_sales_order_detail__cast_type
),

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
