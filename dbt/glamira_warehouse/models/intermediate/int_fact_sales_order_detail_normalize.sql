{{
    config(materialized='view')
}}

WITH int_fact_sales_order_detail__source AS (
    SELECT * FROM {{ ref('stg_fact_sales_order_detail') }}
),

-- 1. CTE unnest cart_products
int_fact_sales_order_detail__unnest_cart AS (
    SELECT
        source.order_id,
        source.device_id,
        source.user_agent,
        source.user_id_db,
        source.email_address,
        source.store_id,
        source.current_url,
        source.time_stamp,
        source.ip,
        CAST(cart_product.product_id AS STRING) AS product_id,
        TRIM(CAST(cart_product.currency AS STRING)) AS raw_currency,
        CAST(cart_product.amount AS INT64) AS amount,
        CAST(cart_product.price AS STRING) AS raw_price
    FROM
        int_fact_sales_order_detail__source AS source
    LEFT JOIN
        UNNEST(source.cart_products) AS cart_product ON TRUE
),

-- 2. CTE tach store_domain tu current_url
int_fact_sales_order_detail__extract_domain AS (
    SELECT
        *,
        REGEXP_EXTRACT(
            LOWER(REGEXP_EXTRACT(current_url, r'^https?://([^/:]+)')),
            r'(\.[^.]+)$'
        ) AS store_domain
    FROM
        int_fact_sales_order_detail__unnest_cart
),

-- 3. CTE lam sach cac ky tu dac biet trong gia tien (dau nhay Thuy Si, phan cach Arap)
int_fact_sales_order_detail__clean_price AS (
    SELECT
        *,
        REPLACE(
            REPLACE(
                REPLACE(TRIM(raw_price), "'", ""),
                '٬', ""
            ),
            '٫', "."
        ) AS cleaned_price
    FROM
        int_fact_sales_order_detail__extract_domain
),

-- 4. CTE chuan hoa dinh dang gia tien ve NUMERIC
int_fact_sales_order_detail__normalize_price AS (
    SELECT
        * EXCEPT(raw_price, cleaned_price),
        CAST(
            CASE
                WHEN NULLIF(cleaned_price, '') IS NULL
                    THEN NULL

                -- European format: 2.962,00 or 1.234.567,89
                WHEN REGEXP_CONTAINS(cleaned_price, r'^\d{1,3}(\.\d{3})+,\d+$')
                    THEN REPLACE(REPLACE(cleaned_price, '.', ''), ',', '.')

                -- US format: 1,094.00 or 1,234,567.89
                WHEN REGEXP_CONTAINS(cleaned_price, r'^\d{1,3}(,\d{3})+\.\d+$')
                    THEN REPLACE(cleaned_price, ',', '')

                -- Decimal comma without a thousands separator: 10,00
                WHEN REGEXP_CONTAINS(cleaned_price, r'^\d+,\d+$')
                    THEN REPLACE(cleaned_price, ',', '.')

                ELSE cleaned_price
            END AS NUMERIC
        ) AS price
    FROM
        int_fact_sales_order_detail__clean_price
),

-- 4. CTE aggregate gio hang
int_fact_sales_order_detail__aggregate_cart AS (
    SELECT
        order_id,
        device_id,
        user_agent,
        user_id_db,
        email_address,
        store_id,
        store_domain,
        time_stamp,
        ip,
        product_id,
        raw_currency,
        SUM(CAST(amount AS INT64)) AS amount,
        AVG(CAST(price AS NUMERIC)) AS price
    FROM
        int_fact_sales_order_detail__normalize_price
    GROUP BY
        order_id,
        device_id,
        user_agent,
        user_id_db,
        email_address,
        store_id,
        store_domain,
        time_stamp,
        ip,
        product_id,
        raw_currency
),

-- 5. CTE map IP sang thong tin dia ly de Fact chi can join voi dim_location
stg_dim_location AS (
    SELECT *
    FROM {{ ref('stg_dim_location') }}
),

int_fact_sales_order_detail__join_location AS (
    SELECT
        cart.*
        COALESCE(loc.location_city_name, 'XNA') AS location_city_name,
        COALESCE(loc.location_region_name, 'XNA') AS location_region_name,
        COALESCE(loc.location_country_code, 'XNA') AS location_country_code,
        COALESCE(loc.location_country_name, 'XNA') AS location_country_name
    FROM
        int_fact_sales_order_detail__aggregate_cart AS cart
    LEFT JOIN
        stg_dim_location AS loc
        ON cart.ip = loc.ip
)

SELECT * FROM int_fact_sales_order_detail__join_location

