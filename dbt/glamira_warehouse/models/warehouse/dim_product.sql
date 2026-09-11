WITH dim_product__source AS (
    SELECT *
    FROM {{ ref('stg_dim_product') }}
),

dim_product__null_handle AS (
    SELECT
        product_key,
        COALESCE(product_id, 'XNA') AS product_id,
        COALESCE(product_name, 'XNA') AS product_name,
        COALESCE(product_sku, 'XNA') AS product_sku,
        COALESCE(product_gender, 'XNA') AS product_gender,
        COALESCE(product_base_price, 0) AS product_base_price,
        COALESCE(product_min_price, 0) AS product_min_price,
        COALESCE(product_max_price, 0) AS product_max_price
    FROM dim_product__source
),

dim_product__special_row AS (
    SELECT 
        * 
    FROM dim_product__null_handle
    UNION ALL
    SELECT
        -1 AS product_key,
        'Unknown' AS product_id,
        'Unknown' AS product_name,
        'Unknown' AS product_sku,
        'Unknown' AS product_gender,
        NUMERIC '0' AS product_base_price,
        NUMERIC '0' AS product_min_price,
        NUMERIC '0' AS product_max_price
),

dim_product__audit AS (
    SELECT
        product_key,
        product_id,
        product_name,
        product_sku,
        product_gender,
        product_base_price,
        product_min_price,
        product_max_price,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM 
        dim_product__special_row
)

SELECT * FROM dim_product__audit
