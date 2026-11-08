-- Singular test: every revenue order must be fully paid (to the penny).
-- Returns the offending rows; zero rows = pass.
select
    order_id,
    gross_amount,
    paid_amount
from {{ ref('fct_orders') }}
where
    is_revenue
    and abs(gross_amount - paid_amount) > 0.01
