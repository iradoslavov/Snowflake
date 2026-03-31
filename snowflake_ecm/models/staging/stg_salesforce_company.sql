{{
    config(materialized='ephemeral')
}}

SELECT
    'SALESFORCE'                    AS source_system,
    sf."Id"                         AS source_company_id,
    sf."Name"                       AS source_company_name,
    OBJECT_CONSTRUCT(
        'ticker',       sf."TickerSymbol",
        'website',      sf."Website",
        'industry',     sf."Industry",
        'city',         sf."BillingCity",
        'country',      sf."BillingCountry",
        'pitchbook_id', sf."pbk__pbId__c",
        'description',  sf."Description"
    )                               AS other_attributes
FROM {{ source('salesforce_ecm', 'account') }} sf
WHERE COALESCE(sf."IsDeleted",       FALSE) = FALSE
  AND COALESCE(sf."IsPersonAccount", FALSE) = FALSE
