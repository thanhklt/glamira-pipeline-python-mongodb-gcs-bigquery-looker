WITH revenue__source AS (
    SELECT *
    FROM {{ref('stg_fact_sales_order_detail')}}
),

dim_date AS (
    SELECT *
    FROM {{ ref('dim_date') }}
),

revenue__join AS (
    SELECT
        d.date_key,
        r.sales_usd_price
    FROM 
        revenue__source AS r
    JOIN
        dim_date AS d
        ON 
            r.date_key = d.date_key
),

revenue__groupby AS (
    SELECT
        date_key AS full_date,
        SUM(sales_usd_price) AS total_sales
    FROM 
        revenue__join
    GROUP BY
        date_key
)
SELECT * FROM revenue__groupby