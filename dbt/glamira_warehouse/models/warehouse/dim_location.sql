WITH dim_location__source AS (
    SELECT *
    FROM {{ ref('stg_dim_location') }}
),

dim_location__distinct AS (
    SELECT DISTINCT
        location_key,
        location_city_name,
        location_region_name,
        location_country_name,
        location_country_code
    FROM 
        dim_location__source
),

dim_location__special_row AS (
    SELECT 
        location_key,
        location_city_name,
        location_region_name,
        location_country_name,
        location_country_code
    FROM 
        dim_location__source
    UNION ALL
    SELECT
        -1 AS location_key,
        'XNA' AS location_city_name,
        'XNA' AS location_region_name,
        'XNA' AS location_country_name,
        'XNA' AS location_country_code
),

dim_location__audit AS (
    SELECT
        location_key,
        location_city_name,
        location_region_name,
        location_country_name,
        location_country_code,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM 
        dim_location__special_row
)

SELECT * FROM dim_location__audit

