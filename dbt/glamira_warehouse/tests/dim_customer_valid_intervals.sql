SELECT *
FROM {{ ref('dim_customer') }}
WHERE start_time >= end_time
