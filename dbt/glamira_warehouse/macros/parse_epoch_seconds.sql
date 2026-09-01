{% macro parse_epoch_seconds(column_name) -%}
    CASE
        WHEN SAFE_CAST(
            NULLIF(TRIM(CAST({{ column_name }} AS STRING)), '') AS INT64
        ) BETWEEN -62135596800 AND 253402300799
        THEN TIMESTAMP_SECONDS(
            SAFE_CAST(NULLIF(TRIM(CAST({{ column_name }} AS STRING)), '') AS INT64)
        )
    END
{%- endmacro %}
