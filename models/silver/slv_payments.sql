-- Silver: typed, de-duplicated payments with amounts converted from cents.
with ranked as (

    select
        *,
        row_number() over (partition by payment_id order by _loaded_at desc) as row_num
    from {{ ref('brz_payments') }}

)

select
    payment_id,
    order_id,
    lower(trim(payment_method)) as payment_method,
    {{ cents_to_currency('cast(amount_cents as integer)') }} as amount,
    lower(trim(payment_status)) as payment_status
from ranked
where row_num = 1
