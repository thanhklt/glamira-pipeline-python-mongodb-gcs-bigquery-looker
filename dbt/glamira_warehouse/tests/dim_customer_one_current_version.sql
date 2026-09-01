SELECT
    customer_device_id,
    COUNTIF(is_current) AS current_version_count
FROM {{ ref('dim_customer') }}
WHERE customer_key != -1
GROUP BY customer_device_id
HAVING COUNTIF(is_current) != 1
