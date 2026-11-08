-- Analyses are compiled (dbt compile) but never run: handy for ad-hoc SQL that uses ref().
select
    full_name,
    country_name,
    lifetime_orders,
    lifetime_revenue
from {{ ref('dim_customers') }}
order by lifetime_revenue desc
limit 10
