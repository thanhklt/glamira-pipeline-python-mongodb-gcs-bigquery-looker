WITH dim_store__source AS (
    SELECT *
    FROM {{ ref('stg_dim_store') }}
),

dim_store__special_row AS (
    SELECT 
        store_key,
        store_id,
        store_domain 
    FROM  
        dim_store__source
    UNION ALL
    SELECT 
        -1 AS store_key,
        'XNA' AS store_id,
        'XNA' AS store_domain
),

dim_store__audit AS (
    SELECT
        store_key,
        store_id,
        store_domain,
        current_date('Asia/Saigon') AS inserted_date,
        'dbt' AS inserted_by,
        current_date('Asia/Saigon') AS updated_date,
        'dbt' AS updated_by
    FROM dim_store__special_row
)

SELECT * FROM dim_store__audit
