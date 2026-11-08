-- Gold: order fact table, one row per order.
{%- set non_revenue = var('non_revenue_statuses') %}

with orders as (

    select
        orders.order_id,
        orders.customer_id,
        orders.order_date,
        orders.order_status,
        totals.item_count,
        totals.payment_count,
        totals.gross_amount,
        totals.paid_amount,
        orders.order_status not in ('{{ non_revenue | join("', '") }}') as is_revenue,  -- noqa: LT05
        orders.updated_at
    from {{ ref('slv_orders') }} as orders
    inner join {{ ref('int_order_totals') }} as totals
        on orders.order_id = totals.order_id

)

select
    order_id,
    customer_id,
    order_date,
    order_status,
    item_count,
    payment_count,
    gross_amount,
    paid_amount,
    is_revenue,
    case when is_revenue then gross_amount else 0 end as net_revenue,
    updated_at
from orders
