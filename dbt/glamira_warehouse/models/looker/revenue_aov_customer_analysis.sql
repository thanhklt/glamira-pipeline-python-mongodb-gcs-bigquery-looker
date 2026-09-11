WITH fact_sale AS (
    SELECT *
    FROM {{ ref('fact_sales_order_detail') }}
),
dim_customer AS (
    SELECT *
    FROM {{ ref('dim_customer') }}
),

revenue_aov_customer_analysis AS (
    SELECT
        SUM(f.sales_usd_price * sales_amount)  AS Revenue,
        COUNT(DISTINCT f.order_id) AS Orders,
        SUM(f.sales_usd_price * sales_amount) / COALESCE(NULLIF(COUNT(DISTINCT f.order_id), 0), 1) AS AOV,
        COUNT(DISTINCT f.customer_key) AS count_customer
    FROM 
        fact_sale AS f
)
SELECT * FROM revenue_aov_customer_analysis