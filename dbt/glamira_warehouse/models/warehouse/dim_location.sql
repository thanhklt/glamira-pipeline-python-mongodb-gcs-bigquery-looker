WITH dim_location__source AS (
    SELECT *
    FROM {{ref('stg_dim_location')}}
),

dim_location__null_handle AS (
    SELECT
        location_key,
        COALESCE(location_city_name, 'XNA') AS location_city_name,
        COALESCE(location_region_name, 'XNA') AS location_region_name,
        COALESCE(location_country_code, 'XNA') AS location_country_code,
        COALESCE(location_country_name, 'XNA') AS location_country_name
    FROM
        dim_location__source
),

dim_location__special_row AS (
    SELECT *
    FROM dim_location__null_handle
    UNION ALL
    SELECT
        -1,
        'XNA',
        'XNA',
        'XNA',
        'XNA'
),

dim_location__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_location__special_row
)

SELECT * FROM dim_location__audit

