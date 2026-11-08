-- Silver: one clean, typed row per customer (latest version wins).
with ranked as (

    select
        *,
        row_number() over (
            partition by customer_id
            order by cast(updated_at as timestamp) desc, _loaded_at desc
        ) as row_num
    from {{ ref('brz_customers') }}
    where customer_id is not null

),

latest as (

    select * from ranked
    where row_num = 1

)

select
    latest.customer_id,
    initcap(trim(latest.first_name)) as first_name,
    initcap(trim(latest.last_name)) as last_name,
    nullif(lower(trim(latest.email)), '') as email,
    initcap(trim(latest.city)) as city,
    countries.country_code,
    countries.country_name,
    cast(latest.signup_date as date) as signup_date,
    cast(latest.updated_at as timestamp) as updated_at,
    latest._loaded_at
from latest
left join {{ ref('country_codes') }} as countries
    on lower(trim(latest.country)) = countries.raw_value
