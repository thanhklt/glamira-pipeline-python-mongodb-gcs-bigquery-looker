WITH fact_sale AS (
    SELECT *
    FROM {{ ref('stg_fact_sales_order_detail') }}
),
dim_customer AS (
    SELECT *
    FROM {{ ref('dim_customer') }}
),

count_record AS (
    SELECT
        SUM(f.sales_usd_price) AS Revenue,
        COUNT(DISTINCT f.order_id) AS Orders,
        SUM(f.sales_usd_price) / COALESCE(NULLIF(COUNT(DISTINCT f.order_id), 0), 1) AS AOV,
        (
            SELECT COUNT(DISTINCT c.customer_device_id)
            FROM dim_customer AS c
        ) AS Customers
    FROM 
        fact_sale AS f
)
SELECT * FROM count_record