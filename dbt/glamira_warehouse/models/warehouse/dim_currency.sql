WITH dim_currency__source AS (
    SELECT *
    FROM {{ ref('stg_dim_currency') }}
),

dim_currency__null_handle AS (
    SELECT
        currency_key,
        COALESCE(currency_code, 'XNA') AS currency_code,
        COALESCE(currency_name, 'XNA') AS currency_name
    FROM dim_currency__source
),

dim_currency__special_row AS (
    SELECT * FROM dim_currency__null_handle
    UNION ALL
    SELECT -1, 'XNA', 'XNA'
),

dim_currency__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_currency__special_row
)

SELECT * FROM dim_currency__audit
