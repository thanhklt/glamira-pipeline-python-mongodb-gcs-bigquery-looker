WITH fact_sales_order_detail AS (
    SELECT *
    FROM {{ref('fact_sales_order_detail')}}
),

dim_product AS (
    SELECT *
    FROM {{ ref('dim_product') }}
),

order_by_product__join AS (
    SELECT
        d.product_key,
        d.product_name,
        f.sales_usd_price
    FROM 
        fact_sales_order_detail AS f
    JOIN
        dim_product AS d
        ON 
            d.product_key = f.product_key
),

order_by_product__groupby AS (
    SELECT
        product_key,
        product_name,
        COUNT(product_name) AS unit_sold
    FROM 
        order_by_product__join
    WHERE
        product_key != -1
    GROUP BY
        product_key, product_name
    ORDER BY 
        unit_sold DESC
)

SELECT * FROM order_by_product__groupby