WITH revenue__source AS (
    SELECT *
    FROM `glamira-project-502214`.`staging`.`stg_fact_sales_order_detail`
),

dim_date AS (
    SELECT *
    FROM `glamira-project-502214`.`warehouse`.`dim_date`
),

revenue__join AS (
    SELECT
        d.day_of_week,
        d.day_name,
        r.sales_usd_price
    FROM 
        revenue__source AS r
    JOIN
        dim_date AS d
        ON 
            r.date_key = d.date_key
),

revenue__order AS(
    SELECT *
    FROM revenue__join
    ORDER BY day_of_week
),

revenue__groupby AS (
    SELECT
        day_of_week,
        day_name,
        SUM(sales_usd_price) AS total_sales,
        COUNT(sales_usd_price) AS count_sales
    FROM 
        revenue__order
    GROUP BY
        day_of_week, day_name
)
SELECT * FROM revenue__groupby