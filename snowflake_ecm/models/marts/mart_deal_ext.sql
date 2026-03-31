{{
    config(
        database='dev_publish',
        schema='public',
        alias='deal_ext',
        materialized='table',
        tags=['publish', 'deal']
    )
}}

/*
  Extended deal attributes sourced from the iLevel UDTF.
  The UDTF call (fn_ilevel) and the hardcoded date should be
  parameterized if this report date needs to vary per-run.
*/

SELECT
    d.ecm_deal_id,
    MAX(CASE WHEN dataitem = 'Business Description (Short)'  THEN dataitemvalue END) AS business_description,
    MAX(CASE WHEN dataitem = 'Code Name'                     THEN dataitemvalue END) AS code_name,
    MAX(CASE WHEN dataitem = 'Asset Type'                    THEN dataitemvalue END) AS asset_type,
    MAX(CASE WHEN dataitem = 'Asset Status'                  THEN dataitemvalue END) AS asset_status,
    MAX(CASE WHEN dataitem = 'Entity Type'                   THEN dataitemvalue END) AS entity_type,
    MAX(CASE WHEN dataitem = 'IsPublic'                      THEN dataitemvalue END) AS is_public,
    MAX(CASE WHEN dataitem = 'Transaction Close Date'        THEN dataitemvalue END) AS transaction_close_date,
    MAX(CASE WHEN dataitem = 'Acquisition Date'              THEN dataitemvalue END) AS acquisition_date,
    MAX(CASE WHEN dataitem = 'Acquisition As Of'             THEN dataitemvalue END) AS acquisition_as_of,
    MAX(CASE WHEN dataitem = 'Eldridge Funding Date'         THEN dataitemvalue END) AS eldridge_funding_date,
    MAX(CASE WHEN dataitem = 'Transaction Exit Date'         THEN dataitemvalue END) AS transaction_exit_date,
    MAX(CASE WHEN dataitem = 'Transaction Type'              THEN dataitemvalue END) AS transaction_type,
    MAX(CASE WHEN dataitem = 'Financing Structure'           THEN dataitemvalue END) AS financing_structure,
    MAX(CASE WHEN dataitem = 'Investment Role'               THEN dataitemvalue END) AS investment_role,
    MAX(CASE WHEN dataitem = 'Covenant Lite'                 THEN dataitemvalue END) AS covenant_lite,
    MAX(CASE WHEN dataitem = 'Covenant Count at Close'       THEN dataitemvalue END) AS covenant_count_at_close,
    MAX(CASE WHEN dataitem = 'Management Rights?'            THEN dataitemvalue END) AS management_rights,
    MAX(CASE WHEN dataitem = 'Board Participation'           THEN dataitemvalue END) AS board_participation,
    MAX(CASE WHEN dataitem = 'Lead Fund'                     THEN dataitemvalue END) AS lead_fund,
    MAX(CASE WHEN dataitem = 'Lender Owned'                  THEN dataitemvalue END) AS lender_owned,
    MAX(CASE WHEN dataitem = 'Senior Agent'                  THEN dataitemvalue END) AS senior_agent,
    MAX(CASE WHEN dataitem = 'Lender Agent Counsel'          THEN dataitemvalue END) AS lender_agent_counsel,
    MAX(CASE WHEN dataitem = 'Sponsor Counsel'               THEN dataitemvalue END) AS sponsor_counsel,
    MAX(CASE WHEN dataitem = 'Sponsor Name'                  THEN dataitemvalue END) AS sponsor_name,
    MAX(CASE WHEN dataitem = 'Sponsor Type'                  THEN dataitemvalue END) AS sponsor_type,
    MAX(CASE WHEN dataitem = 'City'                          THEN dataitemvalue END) AS city,
    MAX(CASE WHEN dataitem = 'State'                         THEN dataitemvalue END) AS state,
    MAX(CASE WHEN dataitem = 'Region'                        THEN dataitemvalue END) AS region,
    MAX(CASE WHEN dataitem = 'Website'                       THEN dataitemvalue END) AS website,
    MAX(CASE WHEN dataitem = 'Eldridge Risk Rating'          THEN dataitemvalue END) AS eldridge_risk_rating,
    MAX(CASE WHEN dataitem = 'Eldridge Overall Assessment'   THEN dataitemvalue END) AS eldridge_overall_assessment,
    MAX(CASE WHEN dataitem = 'Eldridge Pod'                  THEN dataitemvalue END) AS eldridge_pod,
    MAX(CASE WHEN dataitem = 'Eldridge Sector'               THEN dataitemvalue END) AS eldridge_sector,
    MAX(CASE WHEN dataitem = 'Deal Team Lead'                THEN dataitemvalue END) AS deal_team_lead,
    MAX(CASE WHEN dataitem = 'Deal Team Lead - Full Name'    THEN dataitemvalue END) AS deal_team_lead_full_name,
    MAX(CASE WHEN dataitem = 'Deal Team - Partner'           THEN dataitemvalue END) AS deal_team_partner,
    MAX(CASE WHEN dataitem = 'Deal Team - Associate'         THEN dataitemvalue END) AS deal_team_associate,
    MAX(CASE WHEN dataitem = 'Deal Team - VP'                THEN dataitemvalue END) AS deal_team_vp,
    MAX(CASE WHEN dataitem = 'Deal Team - Principal'         THEN dataitemvalue END) AS deal_team_principal,
    MAX(CASE WHEN dataitem = 'Portfolio Analyst'             THEN dataitemvalue END) AS portfolio_analyst
FROM {{ ref('int_ilevel_deal_v3') }} d
JOIN TABLE(dev_publish.kurtosys.fn_ilevel(
    '%',
    TO_DATE('2025-12-31'),
    'Business Description (Short),Code Name,Asset Type,Asset Status,Entity Type,IsPublic,Transaction Close Date,Acquisition Date,Acquisition As Of,Eldridge Funding Date,Transaction Exit Date,Transaction Type,Financing Structure,Investment Role,Covenant Lite,Covenant Count at Close,Management Rights?,Board Participation,Lead Fund,Lender Owned,Senior Agent,Lender Agent Counsel,Sponsor Counsel,Sponsor Name,Sponsor Type,City,State,Region,Website,Eldridge Risk Rating,Eldridge Overall Assessment,Eldridge Pod,Eldridge Sector,Deal Team Lead,Deal Team Lead - Full Name,Deal Team - Partner,Deal Team - Associate,Deal Team - VP,Deal Team - Principal,Portfolio Analyst'
)) fn
    ON  fn.investmentid  = d.source_deal_id
    AND fn."Row Type 2"  = ' -> INVESTMENT -> '
WHERE d.as_of_date    = {{ as_of_date() }}
  AND d.source_system = 'ILEVEL'
GROUP BY d.ecm_deal_id
