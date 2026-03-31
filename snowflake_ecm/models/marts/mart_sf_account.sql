{{
    config(
        database='dev_publish',
        schema='public',
        alias='sf_account',
        materialized='view',
        tags=['publish', 'salesforce']
    )
}}

SELECT
    "Id"                     AS sf_account_id,
    "Name"                   AS sf_account_name,
    "Type"                   AS sf_account_type,
    "ParentId"               AS sf_parent_account_id,
    "AccountSource"          AS sf_account_source,
    "Industry"               AS sf_industry,
    "Ownership"              AS sf_ownership,
    "AnnualRevenue"          AS sf_annual_revenue,
    "NumberOfEmployees"      AS sf_num_employees,
    "TickerSymbol"           AS sf_ticker_symbol,
    "Description"            AS sf_description,
    "Rating"                 AS sf_rating,
    "Sic"                    AS sf_sic_code,
    "SicDesc"                AS sf_sic_description,
    "Website"                AS sf_website,
    "Phone"                  AS sf_phone,
    "Fax"                    AS sf_fax,
    "BillingStreet"          AS sf_billing_street,
    "BillingCity"            AS sf_billing_city,
    "BillingState"           AS sf_billing_state,
    "BillingPostalCode"      AS sf_billing_postal_code,
    "BillingCountry"         AS sf_billing_country,
    "pbk__pbId__c"           AS sf_pitchbook_id,
    "SourceSystemIdentifier" AS sf_source_system_identifier,
    "OwnerId"                AS sf_owner_id,
    "CreatedDate"            AS sf_created_date,
    "LastModifiedDate"       AS sf_last_modified_date
FROM {{ source('salesforce_ecm', 'account') }}
WHERE COALESCE("IsDeleted",       FALSE) = FALSE
  AND COALESCE("IsPersonAccount", FALSE) = FALSE
