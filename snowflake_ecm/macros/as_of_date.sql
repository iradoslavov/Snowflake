{% macro as_of_date() %}
    {#-
      Returns the run-date as a DATE literal.
      Override at invocation time:
        dbt run --vars 'as_of_date: 2024-06-30'
      Defaults to the date on which dbt started the run.
    -#}
    TO_DATE('{{ var("as_of_date", run_started_at.strftime("%Y-%m-%d")) }}')
{% endmacro %}
