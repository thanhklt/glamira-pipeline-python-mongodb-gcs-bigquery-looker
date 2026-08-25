{{ config(materialized='table', schema='staging') }}

SELECT
    farm_fingerprint(concat(raw_location.city_name,'|',raw_location.region_name,'|',raw_location.country_name)) AS location_key,
    city_name AS location_city_name,
    region_name AS location_region_name,
    country_code AS location_country_code,
    country_name AS location_country_name,
    current_timestamp() AS inserted_date,
    'dbt' AS inserted_by,
    current_timestamp() AS updated_date,
    'dbt' AS updated_by
FROM 
    {{ source('landing', 'raw_location') }}