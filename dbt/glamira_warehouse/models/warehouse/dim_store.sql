WITH dim_store__source AS (
    SELECT *
    FROM {{ ref('stg_dim_store') }}
),

dim_store__special_row AS (
    SELECT * FROM dim_store__source
    UNION ALL
    SELECT -1, 'XNA', 'XNA'
),

dim_store__audit AS (
    SELECT
        *,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_store__special_row
)

SELECT * FROM dim_store__audit
