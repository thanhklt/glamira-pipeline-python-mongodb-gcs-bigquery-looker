WITH stg_dim_location__source AS (
    SELECT *
    FROM {{source('landing', 'raw_location')}}
),

stg_dim_location__rename AS (
    SELECT
        city_name AS location_city_name,
        region_name AS location_region_name,
        country_code AS location_country_code,
        country_name AS location_country_name
    FROM stg_dim_location__source
),

stg_dim_location__cast_type AS (
    SELECT
        CAST(location_city_name AS STRING) AS location_city_name,
        CAST(location_region_name AS STRING) AS location_region_name,
        CAST(location_country_code AS STRING) AS location_country_code,
        CAST(location_country_name AS STRING) AS location_country_name
    FROM stg_dim_location__rename
),

stg_dim_location__null_handle AS (
    SELECT
        COALESCE(location_city_name, 'XNA') AS location_city_name,
        COALESCE(location_region_name, 'XNA') AS location_region_name,
        COALESCE(location_country_code, 'XNA') AS location_country_code,
        COALESCE(location_country_name, 'XNA') AS location_country_name
    FROM
        stg_dim_location__cast_type
),

stg_dim_location__dedupe AS (
    SELECT DISTINCT *
    FROM stg_dim_location__null_handle
),

stg_dim_location__genkey AS (
    SELECT
        farm_fingerprint(concat(location_city_name,'|', location_region_name,'|', location_country_code)) AS location_key,
        *
    FROM stg_dim_location__dedupe
)

SELECT * 
FROM stg_dim_location__genkey
