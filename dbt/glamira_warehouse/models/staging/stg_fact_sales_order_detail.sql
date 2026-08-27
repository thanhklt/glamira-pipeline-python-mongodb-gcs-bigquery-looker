WITH stg_fact_sales_order_detail__source AS (
    SELECT *
    FROM {{source('landing', 'raw_mongo')}}
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

stg_fact_sales_order_detail__getcol AS (
    SELECT
        cart_products[SAFE_OFFSET(0)].product_id,
        stg_dim_customer.customer_key
    FROM 
        stg_fact_sales_order_detail__source
    JOIN
        stg_dim_customer
        ON 
            stg_fact_sales_order_detail__source.device_id = stg_dim_customer.customer_device_id
)
SELECT * FROM stg_fact_sales_order_detail__getcol