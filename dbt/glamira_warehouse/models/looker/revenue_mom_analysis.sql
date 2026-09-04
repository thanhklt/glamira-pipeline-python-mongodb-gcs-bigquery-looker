WITH fact_sales AS (
    SELECT
        order_id,
        date_key,
        sales_usd_price
    FROM {{ ref('fact_sales_order_detail') }}
),

dim_date AS (
    SELECT
        date_key,
        year_number,
        month_number,
        month_name
    FROM {{ ref('dim_date') }}
    WHERE year_number > 0 AND date_key != '1970-01-01'
),

sales_with_date AS (
    SELECT
        f.order_id,
        f.sales_usd_price,
        d.year_number,
        d.month_number,
        d.month_name,
        DATE(d.year_number, d.month_number, 1) AS month_start_date
    FROM 
        fact_sales AS f
    JOIN 
        dim_date AS d
        ON f.date_key = d.date_key
),

monthly_revenue AS (
    SELECT
        year_number,
        month_number,
        month_name,
        month_start_date,
        FORMAT('%04d-%02d', year_number, month_number) AS year_month,
        COUNT(DISTINCT order_id) AS total_orders,
        ROUND(SUM(sales_usd_price), 2) AS current_month_revenue
    FROM 
        sales_with_date
    GROUP BY
        year_number,
        month_number,
        month_name,
        month_start_date
),

monthly_comparison AS (
    SELECT
        year_number,
        month_number,
        month_name,
        month_start_date,
        year_month,
        total_orders,
        current_month_revenue,
        LAG(current_month_revenue, 1) OVER (
            ORDER BY year_number, month_number
        ) AS previous_month_revenue,
        LAG(total_orders, 1) OVER (
            ORDER BY year_number, month_number
        ) AS previous_month_orders
    FROM 
        monthly_revenue
),

revenue_mom_analysis AS (
    SELECT
        year_number,
        month_number,
        month_name,
        month_start_date,
        year_month,
        total_orders,
        current_month_revenue,
        previous_month_revenue,
        ROUND(current_month_revenue - COALESCE(previous_month_revenue, 0), 2) AS mom_growth_amount,
        ROUND(
            SAFE_DIVIDE(
                (current_month_revenue - previous_month_revenue),
                previous_month_revenue
            ) * 100,
            2
        ) AS mom_growth_rate_pct,
        (total_orders - COALESCE(previous_month_orders, 0)) AS mom_order_growth_amount
    FROM 
        monthly_comparison
    ORDER BY 
        year_number, 
        month_number
)

SELECT * FROM revenue_mom_analysis
