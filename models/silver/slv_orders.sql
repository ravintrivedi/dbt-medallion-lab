-- Silver: one row per order holding its *latest* status.
--
-- Incremental: each run only reads rows that landed since the last run
-- (_loaded_at watermark) and MERGEs them on order_id, so status changes
-- update existing rows instead of creating duplicates.
{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

with source as (

    select bronze.* from {{ ref('brz_orders') }} as bronze
    where
        bronze.customer_id is not null   -- orphan orders are dropped (see the warn-level test on slv_order_items)
        {% if is_incremental() %}
            -- only rows that landed after the newest row already in this table
            and bronze._loaded_at > (
                select coalesce(max(target_table._loaded_at), '1900-01-01') from {{ this }} as target_table
            )
        {% endif %}

),

deduped as (

    select
        *,
        row_number() over (
            partition by order_id
            order by cast(updated_at as timestamp) desc, _loaded_at desc
        ) as row_num
    from source

)

select
    order_id,
    customer_id,
    cast(order_date as date) as order_date,
    case lower(trim(status))
        when 'complete' then 'completed'
        when 'canceled' then 'cancelled'
        else lower(trim(status))
    end as order_status,
    cast(updated_at as timestamp) as updated_at,
    _loaded_at
from deduped
where row_num = 1
