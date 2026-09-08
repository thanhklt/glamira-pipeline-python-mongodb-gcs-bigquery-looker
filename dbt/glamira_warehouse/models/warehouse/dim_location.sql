WITH dim_location__source AS (
    SELECT *
    FROM {{ref('stg_dim_location')}}
),


dim_location__special_row AS (
    SELECT 
        *
    FROM 
        dim_location__source
    UNION ALL
    SELECT
        -1 AS location_key,
        'XNA' AS country_code,
        'XNA' AS country_name,
        'XNA' AS state_name,
        'XNA' AS city_name
),

dim_location__audit AS (
    SELECT
        location_key,
        country_code,
        country_name,
        state_name,
        city_name,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM 
        dim_location__special_row
)

SELECT * FROM dim_location__audit

