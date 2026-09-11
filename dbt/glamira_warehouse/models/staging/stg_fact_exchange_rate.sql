WITH exchange_rate__source AS (
    SELECT *
    FROM {{source('landing', 'raw_exchange_rate')}}
),

stg_dim_currency AS (
    SELECT
        currency_key,
        currency_code
    FROM {{ ref('stg_dim_currency') }}
),

stg_dim_date AS (
    SELECT date_key
    FROM {{ ref('stg_dim_date') }}
),


exchange_rate__cast_type AS (
    SELECT
        SAFE_CAST(date AS DATE) AS date_key,
        TO_JSON(rates) AS rates_json
    FROM exchange_rate__source
),

exchange_rate__flattened AS (
    SELECT
        cast_type.date_key,
        UPPER(currency_code) AS currency_code,
        LAX_FLOAT64(cast_type.rates_json[currency_code]) AS rate_from_usd
    FROM 
        exchange_rate__cast_type AS cast_type
    CROSS JOIN 
        UNNEST(JSON_KEYS(cast_type.rates_json, 1)) AS currency_code
),


stg_fact_exchange_rate__joined AS (
    SELECT
        exchange_rate.date_key,
        currency.currency_key,
        SAFE_DIVIDE(1.0, exchange_rate.rate_from_usd) AS rate_to_usd
    FROM 
        exchange_rate__flattened AS exchange_rate
    JOIN 
        stg_dim_currency AS currency
            ON 
                exchange_rate.currency_code = currency.currency_code
    JOIN 
        stg_dim_date AS date_dimension
        ON 
            exchange_rate.date_key = date_dimension.date_key
    WHERE 
        exchange_rate.rate_from_usd IS NOT NULL

    UNION ALL

    -- USD is the base currency and is not returned by Frankfurter.
    -- Its rate_to_usd is always 1.
    SELECT
        date_dimension.date_key,
        currency.currency_key,
        CAST(1 AS FLOAT64) AS rate_to_usd
    FROM
        stg_dim_date AS date_dimension
    JOIN
        stg_dim_currency AS currency
        ON currency.currency_code = 'USD'
),

stg_fact_exchange_rate__dedupe AS (
    SELECT DISTINCT *
    FROM stg_fact_exchange_rate__joined
),

stg_fact_exchange_rate__genkey AS (
    SELECT
        FARM_FINGERPRINT(
            CONCAT(
                CAST(date_key AS STRING),
                '|',
                CAST(currency_key AS STRING)
            )
        ) AS exchange_rate_key,
        date_key,
        currency_key,
        rate_to_usd
    FROM stg_fact_exchange_rate__dedupe
)

SELECT *
FROM stg_fact_exchange_rate__genkey
