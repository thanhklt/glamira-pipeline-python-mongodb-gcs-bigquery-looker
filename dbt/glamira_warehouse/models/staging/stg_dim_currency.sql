WITH stg_dim_currency__source AS (
    SELECT *
    FROM {{source('landing', 'raw_mongo')}}
),


stg_dim_currency__get_raw_currency AS (
    SELECT
        cart_products[SAFE_OFFSET(0)].currency AS raw_currency
    FROM stg_dim_currency__source
),

stg_dim_currency__trim AS (
    SELECT
        trim(raw_currency) as raw_currency
    FROM stg_dim_currency__get_raw_currency
),

stg_dim_currency__mapping AS (
    SELECT
        tbl2.currency_code,
        tbl2.currency_name
    FROM
        stg_dim_currency__trim AS tbl1
    INNER JOIN 
        {{ref('currency_mapping')}} AS tbl2
        ON tbl1.raw_currency = tbl2.raw_currency
),

stg_dim_currency__dedupe AS (
    SELECT DISTINCT *
    FROM stg_dim_currency__mapping
),

stg_dim_currency__genkey AS (
    SELECT
        farm_fingerprint(currency_code) AS currency_key,
        *
    FROM stg_dim_currency__dedupe
)

SELECT * FROM stg_dim_currency__genkey
