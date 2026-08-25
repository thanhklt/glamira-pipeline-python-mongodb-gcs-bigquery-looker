{{ config(materialized='table', schema='staging') }}

with checkout_currencies as (
    select distinct
        trim(cart_product.currency) as raw_currency,
        lower(regexp_extract(raw.current_url, r'^https?://([^/:]+)')) as domain
    from {{ source('landing', 'raw_mongo') }} as raw
    cross join unnest(raw.cart_products) as cart_product
    where raw.collection = 'checkout_success'
      and nullif(trim(cart_product.currency), '') is not null
      and not regexp_contains(
          lower(coalesce(regexp_extract(raw.current_url, r'^https?://([^/:]+)'), '')),
          r'^(dev|stage)|\.local$'
      )
),

mapped_currencies as (
    select distinct
        mapping.currency_code,
        mapping.currency_name
    from checkout_currencies as source
    inner join {{ ref('currency_mapping') }} as mapping
        on source.raw_currency = mapping.raw_currency
       and (
           mapping.domain_suffix = '*'
           or ends_with(source.domain, mapping.domain_suffix)
       )
)

select
    farm_fingerprint(currency_code) as currency_key,
    currency_code,
    currency_name,
    current_timestamp() as inserted_date,
    'dbt' as inserted_by,
    current_timestamp() as updated_date,
    'dbt' as updated_by
from mapped_currencies
