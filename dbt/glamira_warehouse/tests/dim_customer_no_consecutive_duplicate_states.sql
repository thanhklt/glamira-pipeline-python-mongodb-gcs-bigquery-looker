WITH ordered_versions AS (
    SELECT
        *,
        ROW_NUMBER() OVER customer_history AS version_number,
        LAG(customer_user_agent) OVER customer_history AS previous_user_agent,
        LAG(customer_user_id_db) OVER customer_history AS previous_user_id_db,
        LAG(customer_email_address) OVER customer_history AS previous_email_address
    FROM {{ ref('stg_dim_customer') }}
    WINDOW customer_history AS (
        PARTITION BY customer_device_id
        ORDER BY start_time
    )
)

SELECT *
FROM ordered_versions
WHERE version_number > 1
  AND customer_user_agent IS NOT DISTINCT FROM previous_user_agent
  AND customer_user_id_db IS NOT DISTINCT FROM previous_user_id_db
  AND customer_email_address IS NOT DISTINCT FROM previous_email_address
