{{
    config(
        materialized='incremental',
        unique_key='detail_key',
        incremental_strategy='merge'
    )
}}

WITH fact_sales_order_detail__source AS (
    SELECT *
    FROM {{ref('stg_fact_sales_order_detail')}}

    {% if is_incremental() %} -- Chỉ chạy nếu là incremental
    WHERE detail_key NOT IN (
        SELECT detail_key
        FROM {{ this }}
    )
    {% endif %}
),


fact_sales_order_detail__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM
        fact_sales_order_detail__source
)

SELECT * FROM fact_sales_order_detail__audit

