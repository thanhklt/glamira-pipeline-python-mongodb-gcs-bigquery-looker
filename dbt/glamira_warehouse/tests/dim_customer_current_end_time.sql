SELECT *
FROM {{ ref('dim_customer') }}
WHERE customer_key != -1
  AND (
      (is_current AND end_time != TIMESTAMP '9999-01-01 00:00:00+00')
      OR (NOT is_current AND end_time = TIMESTAMP '9999-01-01 00:00:00+00')
  )
