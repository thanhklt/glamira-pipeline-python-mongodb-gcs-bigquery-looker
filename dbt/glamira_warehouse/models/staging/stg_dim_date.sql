WITH stg_dim_date__source AS (
    SELECT *
    FROM {{source('landing','raw_mongo')}}
),

stg_dim_date__get_local_time AS (
    SELECT local_time
    FROM stg_dim_date__source
),

-- Trong bigquery local_time dang la string
stg_dim_date__cast_type AS (
    SELECT cast(local_time AS datetime) AS local_time
    FROM stg_dim_date__get_local_time
),

stg_dim_date__get_date AS (
    SELECT cast(format_date('%Y-%m-%d', local_time) AS date) AS full_date
    FROM stg_dim_date__cast_type
),

stg_dim_date__dedupe AS (
    SELECT DISTINCT *
    FROM stg_dim_date__get_date
),

-- Có ngày 2026-01-07
stg_dim_date__valid AS (
    SELECT *
    FROM stg_dim_date__dedupe
    WHERE full_date <= CURRENT_DATE("Asia/Saigon")
),

stg_dim_date__extract AS (
    SELECT 
        full_date AS date_key,
        extract(dayofweek from full_date) as day_of_week,
        format_date('%A', full_date) as day_name,
        extract(day from full_date) as day_of_month,
        extract(dayofyear from full_date) as day_of_year,
        extract(isoweek from full_date) as week_of_year,
        extract(month from full_date) as month_number,
        format_date('%B', full_date) as month_name,
        extract(quarter from full_date) as quarter_number,
        extract(year from full_date) as year_number,
        extract(dayofweek from full_date) in (1, 7) as is_weekend
    FROM stg_dim_date__valid
)

SELECT * FROM stg_dim_date__extract
