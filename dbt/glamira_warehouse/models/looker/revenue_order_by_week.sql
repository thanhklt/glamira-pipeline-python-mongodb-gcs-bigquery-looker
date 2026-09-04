WITH fact_sales_order_detail AS (
    SELECT *
    FROM {{ref('fact_sales_order_detail')}}
),

dim_date AS (
    SELECT *
    FROM {{ref('dim_date')}}
),

revenue_order_by_week__join AS (
    SELECT
        d.day_of_week,
        d.day_name,
        f.sales_usd_price,
        f.order_id
    FROM 
        fact_sales_order_detail AS f
    JOIN
        dim_date AS d
        ON 
            f.date_key = d.date_key
),

revenue_order_by_week__groupby AS (
    SELECT
        day_of_week,
        day_name,
        ROUND(SUM(sales_usd_price), 2) AS total_sales,
        COUNT(DISTINCT order_id) AS total_orders
    FROM 
        revenue_order_by_week__join
    GROUP BY
        day_of_week, day_name
    ORDER BY 
        day_of_week
)
SELECT * FROM revenue_order_by_week__groupby