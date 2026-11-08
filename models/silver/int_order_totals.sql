-- Ephemeral helper: never materialised, dbt inlines it as a CTE wherever it is ref'd.
{{ config(materialized='ephemeral') }}

with line_totals as (

    select
        items.order_id,
        count(*) as item_count,
        sum(items.quantity * products.unit_price) as gross_amount
    from {{ ref('slv_order_items') }} as items
    inner join {{ ref('slv_products') }} as products
        on items.product_id = products.product_id
    group by items.order_id

),

payment_totals as (

    select
        order_id,
        count(*) as payment_count,
        sum(amount) filter (where payment_status = 'success') as paid_amount
    from {{ ref('slv_payments') }}
    group by order_id

)

select
    line_totals.order_id,
    line_totals.item_count,
    line_totals.gross_amount,
    coalesce(payment_totals.payment_count, 0) as payment_count,
    coalesce(payment_totals.paid_amount, 0) as paid_amount
from line_totals
left join payment_totals
    on line_totals.order_id = payment_totals.order_id
