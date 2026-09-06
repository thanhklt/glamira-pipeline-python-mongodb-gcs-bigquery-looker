WITH fact_exchange_rate AS (
    SELECT *
    FROM {{ref('fact_exchange_rate')}}
),

dim_date AS (
    SELECT *
    FROM {{ref('dim_date')}}
)

SELECT *
FROM fact_exchange_rate
WHERE date_key NOT IN (SELECT date_key FROM dim_date)