-- Gold: daily KPI table that feeds the exec dashboard (see exposure).
select
    order_date,
    count(*) as total_orders,
    count(*) filter (where is_revenue) as revenue_orders,
    sum(net_revenue) as net_revenue,
    round(sum(net_revenue) / nullif(count(*) filter (where is_revenue), 0), 2) as avg_order_value
from {{ ref('fct_orders') }}
group by order_date
