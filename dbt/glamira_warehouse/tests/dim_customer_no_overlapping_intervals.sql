WITH ordered_versions AS (
    SELECT
        *,
        LAG(end_time) OVER (
            PARTITION BY customer_device_id
            ORDER BY start_time
        ) AS previous_end_time
    FROM {{ ref('dim_customer') }}
    WHERE customer_key != -1
)

SELECT *
FROM ordered_versions
WHERE start_time < previous_end_time
