{#- Custom generic test: fails for any row where the column is below zero. -#}
{% test non_negative(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
