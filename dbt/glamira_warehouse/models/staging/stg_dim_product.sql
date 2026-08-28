WITH stg_dim_product__source AS (
    SELECT *
    FROM {{source('landing', 'raw_product')}}
),

stg_dim_product__get_col AS (
    SELECT
        product_id,
        name,
        sku,
        gender,
        price,
        min_price,
        max_price
    FROM stg_dim_product__source
),

stg_dim_product__trim AS (
    SELECT
        product_id,
        trim(name) as name,
        trim(sku) as sku,
        gender,
        price,
        min_price,
        max_price
    FROM stg_dim_product__get_col

),

stg_dim_product__cast_type AS (
    SELECT
        CAST(product_id AS STRING) AS product_id,
        CAST(name AS STRING) AS name,
        CAST(sku AS STRING) AS sku,
        CAST(gender AS STRING) AS gender,
        CAST(price AS NUMERIC) AS price,
        CAST(min_price AS NUMERIC) AS min_price,
        CAST(max_price AS NUMERIC) AS max_price
    FROM stg_dim_product__trim
),

stg_dim_product__rename AS (
    SELECT
        product_id AS product_id,
        name AS product_name,
        sku AS product_sku,
        gender AS product_gender,
        price AS product_base_price,
        min_price AS product_min_price,
        max_price AS product_max_price
    FROM stg_dim_product__cast_type
),

stg_dim_product__dedupe AS (
    SELECT DISTINCT *
    FROM stg_dim_product__rename
),

stg_dim__product__genkey AS (
    SELECT
        farm_fingerprint(product_id) AS product_key,
        *
    FROM stg_dim_product__dedupe
)

SELECT * FROM stg_dim__product__genkey
