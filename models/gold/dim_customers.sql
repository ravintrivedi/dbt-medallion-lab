-- Gold: customer dimension (SCD type 1 - current state) enriched with order behaviour.
-- Full change history lives in the snp_customers snapshot.
with orders as (

    select
        customer_id,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        count(*) as lifetime_orders,
        sum(net_revenue) as lifetime_revenue
    from {{ ref('fct_orders') }}
    group by customer_id

)

select
    customers.customer_id,
    customers.first_name || ' ' || customers.last_name as full_name,
    customers.email,
    customers.city,
    customers.country_code,
    customers.country_name,
    customers.signup_date,
    orders.first_order_date,
    orders.last_order_date,
    coalesce(orders.lifetime_orders, 0) as lifetime_orders,
    coalesce(orders.lifetime_revenue, 0) as lifetime_revenue,
    case
        when coalesce(orders.lifetime_revenue, 0) >= 500 then 'vip'
        when coalesce(orders.lifetime_revenue, 0) > 0 then 'active'
        else 'prospect'
    end as customer_segment
from {{ ref('slv_customers') }} as customers
left join orders
    on customers.customer_id = orders.customer_id
