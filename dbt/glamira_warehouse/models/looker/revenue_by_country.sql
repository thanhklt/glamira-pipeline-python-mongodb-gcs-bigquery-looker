WITH fact_sales_order_detail AS (
    SELECT *
    FROM {{ref('fact_sales_order_detail')}}
),

dim_location AS (
    SELECT *
    FROM {{ ref('dim_location') }}
),

revenue_by_country__join AS (
    SELECT
        d.*,
        f.sales_usd_price
    FROM 
        dim_location AS d
    JOIN
        fact_sales_order_detail AS f
        ON 
            f.location_key = d.location_key
),

revenue_by_country__groupby AS (
    SELECT        
        location_country_name,
        location_country_code,
        SUM(sales_usd_price) AS Revenue
    FROM 
        revenue_by_country__join
    GROUP BY
        location_country_name,
        location_country_code
    ORDER BY
        Revenue DESC
)

SELECT * FROM revenue_by_country__groupby
