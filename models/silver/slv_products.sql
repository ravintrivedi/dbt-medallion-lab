-- Silver: typed product catalogue with conformed categories.
with ranked as (

    select
        *,
        row_number() over (partition by product_id order by _loaded_at desc) as row_num
    from {{ ref('brz_products') }}

)

select
    product_id,
    trim(product_name) as product_name,
    lower(trim(category)) as category,
    {{ cents_to_currency('cast(unit_price_cents as integer)') }} as unit_price,
    lower(trim(is_active)) in ('true', '1', 'yes') as is_active
from ranked
where row_num = 1
