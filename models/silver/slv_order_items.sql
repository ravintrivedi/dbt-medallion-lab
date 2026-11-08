-- Silver: typed, de-duplicated order lines.
with ranked as (

    select
        *,
        row_number() over (partition by order_item_id order by _loaded_at desc) as row_num
    from {{ ref('brz_order_items') }}

)

select
    order_item_id,
    order_id,
    product_id,
    cast(quantity as integer) as quantity
from ranked
where row_num = 1
