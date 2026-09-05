WITH unique_customer AS (
    SELECT COUNT(DISTINCT customer_device_id) AS total_unique_customers
    FROM {{ ref('dim_customer') }}
    WHERE customer_key != -1
),

active_customer AS (
    SELECT COUNT(DISTINCT customer_device_id) AS total_active_customers
    FROM {{ ref('dim_customer') }}
    WHERE customer_key != -1 AND is_current = TRUE
)

SELECT 
    unique_customer.total_unique_customers,
    active_customer.total_active_customers
FROM unique_customer
CROSS JOIN active_customer
WHERE unique_customer.total_unique_customers != active_customer.total_active_customers
