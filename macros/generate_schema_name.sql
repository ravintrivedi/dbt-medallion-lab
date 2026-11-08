{#
    Controls which schema each model lands in.

      target   | +schema: silver  ->  schema
      ---------+------------------------------------
      prod     | silver
      dev      | dev_silver         (DBT_SCHEMA=dev)
      ci       | ci_pr_42_silver    (DBT_SCHEMA=ci_pr_42)

    So prod gets clean bronze/silver/gold schemas, while every developer and
    every pull request gets an isolated sandbox in the same database.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
