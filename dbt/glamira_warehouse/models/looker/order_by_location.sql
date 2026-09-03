WITH order_by_location__source AS (
    SELECT *
    FROM {{ref('stg_fact_sales_order_detail')}}
),

dim_location AS (
    SELECT *
    FROM {{ ref('dim_location') }}
),

order_by_location__join AS (
    SELECT
        l.*,
        o.sales_usd_price
    FROM 
        order_by_location__source AS o
    JOIN
        dim_location AS l
        ON 
            o.location_key = l.location_key
),

order_by_location__groupby AS (
    SELECT        
        location_country_name,
        location_country_code,
        SUM(sales_usd_price) AS Revenue
    FROM 
        order_by_location__join
    GROUP BY
        location_country_name,
        location_country_code
    ORDER BY
        Revenue DESC
)

SELECT * FROM order_by_location__groupby
