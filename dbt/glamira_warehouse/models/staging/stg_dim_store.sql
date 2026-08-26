WITH stg_dim_store__source AS (
    SELECT * FROM {{ source('landing','raw_mongo') }}
),

stg_dim_store__get_col AS (
    SELECT 
        store_id,
        current_url
    FROM stg_dim_store__source
),

stg_dim_store__domain_name AS (
    SELECT
        store_id,
        regexp_extract(
            lower(regexp_extract(current_url, r'^https?://([^/:]+)')),
            r'(\.[^.]+)$'
        ) AS store_domain
    FROM stg_dim_store__get_col
),

stg_dim_store__distinct AS (
    SELECT DISTINCT *
    FROM stg_dim_store__domain_name
),

stg_dim_store__genkey AS (
    SELECT
        farm_fingerprint(store_id) as store_key,
        *
    FROM stg_dim_store__distinct
)

SELECT * FROM stg_dim_store__genkey