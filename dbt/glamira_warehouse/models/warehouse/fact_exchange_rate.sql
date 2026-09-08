{{
    config(
        materialized='incremental',
        unique_key=['date_key', 'currency_key'],
        incremental_strategy='merge'
    )
}}

WITH fact_exchange_rate__source AS (
    SELECT *
    FROM {{ref('stg_fact_exchange_rate')}}

    {% if is_incremental() %} -- Chỉ chạy nếu là incremental
    WHERE exchange_rate_key NOT IN (
        SELECT exchange_rate_key
        FROM {{ this }}
    )
    {% endif %}
),

fact_exchange_rate__null_handle AS (
    SELECT
        exchange_rate_key,
        COALESCE(date_key, '1970-01-01') AS date_key,
        COALESCE(currency_key, -1) AS currency_key,
        rate_to_usd
    FROM 
        fact_exchange_rate__source
),

fact_exchange_rate__audit AS (
    SELECT
        exchange_rate_key,
        date_key,
        currency_key,
        rate_to_usd,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM
        fact_exchange_rate__null_handle
)

SELECT * FROM fact_exchange_rate__audit

