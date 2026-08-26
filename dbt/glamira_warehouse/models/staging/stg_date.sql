{{ config(materialized='table', schema='staging') }}

with date_spine as (
    select full_date
    from unnest(
        generate_date_array(date '2000-01-01',current_date('Asia/Ho_Chi_Minh'))
    ) as full_date
)

select
    cast(format_date('%Y%m%d', full_date) as int64) as date_key,
    full_date,
    extract(dayofweek from full_date) as day_of_week,
    format_date('%A', full_date) as day_name,
    extract(day from full_date) as day_of_month,
    extract(dayofyear from full_date) as day_of_year,
    extract(isoweek from full_date) as week_of_year,
    extract(month from full_date) as month_number,
    format_date('%B', full_date) as month_name,
    extract(quarter from full_date) as quarter_number,
    extract(year from full_date) as year_number,
    extract(dayofweek from full_date) in (1, 7) as is_weekend,
    current_timestamp() as inserted_date,
    'dbt' as inserted_by,
    current_timestamp() as updated_date,
    'dbt' as updated_by
from date_spine
