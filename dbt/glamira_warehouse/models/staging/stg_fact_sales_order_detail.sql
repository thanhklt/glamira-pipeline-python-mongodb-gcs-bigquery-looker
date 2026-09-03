WITH stg_fact_sales_order_detail__raw_mongo_source AS (
    SELECT *
    FROM {{source('landing', 'raw_mongo')}}
),

stg_fact_sales_order_detail__filler AS (
    SELECT *
    FROM stg_fact_sales_order_detail__raw_mongo_source
    WHERE collection = 'checkout_success'
),

stg_fact_sales_order_detail__raw_location_source AS (
    SELECT *
    FROM {{source('landing', 'raw_location')}}
),

stg_fact_sales_order_detail__raw_location_dedupe AS (
    SELECT DISTINCT
        ip,
        city_name,
        region_name,
        country_code,
        country_name
    FROM stg_fact_sales_order_detail__raw_location_source
),

stg_fact_sales_order_detail__raw_product_source AS (
    SELECT *
    FROM {{source('landing', 'raw_product')}}
),


currency_mapping AS (
    SELECT *
    FROM {{ref('currency_mapping')}}
),

stg_fact_exchange_rate AS (
    SELECT *
    FROM {{ref('stg_fact_exchange_rate')}}
),

stg_dim_currency AS (
    SELECT *
    FROM {{ ref('stg_dim_currency') }}
),

stg_dim_customer AS (
    SELECT *
    FROM {{ ref('stg_dim_customer') }}
),

stg_dim_date AS (
    SELECT *
    FROM {{ ref('stg_dim_date') }}
),

stg_dim_location AS (
    SELECT *
    FROM {{ ref('stg_dim_location') }}
),

stg_dim_product AS (
    SELECT *
    FROM {{ ref('stg_dim_product') }}
),

stg_dim_store AS (
    SELECT *
    FROM {{ ref('stg_dim_store') }}
),

-- Lay nhung cot khong phai khoa chinh tu raw_mongo
stg_fact_sales_order_detail__retrieve AS (
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
        stg_fact_sales_order_detail__filler AS source
    LEFT JOIN
        UNNEST(source.cart_products) AS cart_product ON TRUE
),

-- Lấy location_key
stg_fact_sales_sales_order_detail__joined__location AS (
    SELECT
        current_fact.*,
        dim.location_key
    FROM 
        stg_fact_sales_order_detail__retrieve AS current_fact
    LEFT JOIN
        stg_fact_sales_order_detail__raw_location_dedupe AS source
        ON
            current_fact.ip = source.ip
    LEFT JOIN
        stg_dim_location AS dim
        ON
            dim.location_city_name = source.city_name AND
            dim.location_region_name = source.region_name AND
            dim.location_country_code = source.country_code AND
            dim.location_country_name = source.country_name
),


-- Lấy customer_key
stg_fact_sales_sales_order_detail__joined__customer AS (
    SELECT
        current_fact.*,
        dim_customer.customer_key
    FROM
        stg_fact_sales_sales_order_detail__joined__location AS current_fact
    LEFT JOIN
        stg_dim_customer AS dim_customer
        ON
            NULLIF(TRIM(CAST(current_fact.device_id AS STRING)), '')
                = dim_customer.customer_device_id
            AND current_fact.record_time >= dim_customer.start_time
            AND current_fact.record_time < dim_customer.end_time
),

-- Lay product_key
stg_fact_sales_order_detail__joined__product AS (
    SELECT
        current_fact.*,
        dim_product.product_key
    FROM
        stg_fact_sales_sales_order_detail__joined__customer AS current_fact
    LEFT JOIN
        stg_dim_product AS dim_product
        ON CAST(current_fact.product_id AS STRING) = dim_product.product_id
),

-- Lay currency_key
stg_fact_sales_order_detail__joined__currency AS (
    SELECT
        current_fact.*,
        dim_currency.currency_key
    FROM
        stg_fact_sales_order_detail__joined__product AS current_fact
    LEFT JOIN
        currency_mapping AS mapping
        ON TRIM(current_fact.raw_currency) = mapping.raw_currency
    LEFT JOIN
        stg_dim_currency AS dim_currency
        ON mapping.currency_code = dim_currency.currency_code
),

-- Lay store_key
stg_fact_sales_order_detail__joined__store AS (
    SELECT
        current_fact.*,
        dim_store.store_key
    FROM
        stg_fact_sales_order_detail__joined__currency AS current_fact
    LEFT JOIN
        stg_dim_store AS dim_store
        ON
            current_fact.store_id = dim_store.store_id AND
            regexp_extract(
                lower(regexp_extract(current_fact.current_url, r'^https?://([^/:]+)')),
                r'(\.[^.]+)$'
            ) = dim_store.store_domain
),

-- Lay date_key
stg_fact_sales_order_detail__joined__date AS (
    SELECT
        current_fact.*,
        dim_date.date_key
    FROM
        stg_fact_sales_order_detail__joined__store AS current_fact
    LEFT JOIN
        stg_dim_date AS dim_date
        ON CAST(CAST(current_fact.local_time AS DATETIME) AS DATE) = dim_date.date_key
),


-- Lấy measurement
stg_fact_sales_order_detail__measurement AS (
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
    FROM stg_fact_sales_order_detail__joined__date
),

stg_fact_sales_order_detail__normalize_price AS (
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
    FROM stg_fact_sales_order_detail__measurement
),

stg_fact_sales_order_detail__get_usd_price AS (
    SELECT
        stg_fact_sales.customer_key,
        stg_fact_sales.product_key,
        stg_fact_sales.location_key,
        stg_fact_sales.currency_key,
        stg_fact_sales.store_key,
        stg_fact_sales.order_id,
        stg_fact_sales.date_key,
        stg_fact_sales.local_time,
        stg_fact_sales.time_stamp,
        stg_fact_sales.ip,
        stg_fact_sales.amount,
        stg_fact_sales.price,
        ROUND(
            stg_fact_sales.price * stg_fact_exchange_rate.rate_to_usd,
            2
        ) AS sales_usd_price
    FROM
        stg_fact_sales_order_detail__normalize_price AS stg_fact_sales
    LEFT JOIN
        stg_fact_exchange_rate
        ON 
            stg_fact_sales.currency_key = stg_fact_exchange_rate.currency_key AND
            stg_fact_sales.date_key = stg_fact_exchange_rate.date_key
),

stg_fact_sales_order_detail__rename AS (
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
    FROM stg_fact_sales_order_detail__get_usd_price
),


stg_fact_sales_order_detail__null_handle AS (
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
        stg_fact_sales_order_detail__rename
),

stg_fact_sales_order_detail__genkey AS (
    SELECT
        FARM_FINGERPRINT(CONCAT(order_id, '|', product_key)) AS detail_key,
        *
    FROM stg_fact_sales_order_detail__null_handle
)

SELECT * FROM stg_fact_sales_order_detail__genkey
