WITH dim_date__source AS (
    SELECT *
    FROM {{ ref('stg_dim_date') }}
),

dim_date__null_handle AS (
    SELECT
        date_key,
        COALESCE(day_of_week, 0) AS day_of_week,
        COALESCE(day_name, 'XNA') AS day_name,
        COALESCE(day_of_month, 0) AS day_of_month,
        COALESCE(day_of_year, 0) AS day_of_year,
        COALESCE(week_of_year, 0) AS week_of_year,
        COALESCE(month_number, 0) AS month_number,
        COALESCE(month_name, 'XNA') AS month_name,
        COALESCE(quarter_number, 0) AS quarter_number,
        COALESCE(year_number, 0) AS year_number,
        COALESCE(is_weekend, FALSE) AS is_weekend
    FROM dim_date__source
),

dim_date__special_row AS (
    SELECT * FROM dim_date__null_handle
    UNION ALL
    SELECT
        '1970-01-01', 0, 'XNA', 0, 0, 0, 0, 'XNA', 0, 0, FALSE
),

dim_date__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_date__special_row
)

SELECT * FROM dim_date__audit
