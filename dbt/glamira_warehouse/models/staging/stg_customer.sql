{{ config(materialized='view', schema='staging') }}

with customer_src as (
    select
        trim(device_id) as device_id,
        max(nullif(trim(user_agent), '')) as user_agent,
        max(nullif(trim(user_id_db), '')) as user_id_db,
        max(nullif(trim(email_address), '')) as email_address
    from {{ source('landing', 'raw_mongo') }}
    where nullif(trim(device_id), '') is not null
    group by trim(device_id)
)

select
    farm_fingerprint(device_id) as customer_key,
    user_agent as customer_user_agent,
    user_id_db as customer_user_id_db,
    device_id as customer_device_id,
    email_address as customer_email_address,
    current_date('Asia/Ho_Chi_Minh') as start_date,
    '9999-1-1' as end_date,
    true as is_current,
    -- current_timestamp() as inserted_date,
    -- 'dbt' as inserted_by,
    -- current_timestamp() as updated_date,
    -- 'dbt' as updated_by
from customer_src
