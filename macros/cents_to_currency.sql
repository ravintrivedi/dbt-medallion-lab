{#- Convert an integer amount in minor units (pence/cents) to a decimal currency amount. -#}
{% macro cents_to_currency(column_name, scale=2) -%}
    round(cast({{ column_name }} as numeric) / 100, {{ scale }})
{%- endmacro %}
