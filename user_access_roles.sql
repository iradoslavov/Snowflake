--------------------------------------------------------------------------------
-- user_access_roles.sql
--
-- Table function that returns every user who can access a given object (or who
-- holds a given role), together with every role-hierarchy path and its depth.
--
-- Two modes:
--   1. OBJECT mode  – pass an object type (TABLE, VIEW, …) + its coordinates.
--   2. ROLE mode    – pass 'ROLE' as the first argument + the role name.
--
-- Uses SNOWFLAKE.ACCOUNT_USAGE views (up to 2-hour latency).
-- The calling role needs IMPORTED PRIVILEGES on the SNOWFLAKE database.
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_user_access_paths(
    P_STARTING_POINT_TYPE  VARCHAR,            -- 'ROLE', 'TABLE', 'VIEW', …
    P_NAME                 VARCHAR,            -- object name  OR  role name
    P_DATABASE             VARCHAR DEFAULT NULL,
    P_SCHEMA               VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    USER_NAME                VARCHAR,
    OBJECT_TYPE              VARCHAR,
    OBJECT_FQN               VARCHAR,
    PRIVILEGE                VARCHAR,
    DIRECTLY_PRIVILEGED_ROLE VARCHAR,
    ROLE_GRANTED_TO_USER     VARCHAR,
    ACCESS_PATH              VARCHAR,
    PATH_DEPTH               INTEGER
)
AS
$$
    WITH RECURSIVE

    -- Pre-deduplicated role-to-role grants (removes duplicates caused by
    -- multiple grantors, GRANT OPTION differences, etc.)
    role_grants AS (
        SELECT DISTINCT
            name         AS child_role,
            grantee_name AS parent_role
        FROM snowflake.account_usage.grants_to_roles
        WHERE granted_on  = 'ROLE'
          AND deleted_on IS NULL
    ),

    -- Seed rows – depends on the starting-point mode
    base_grants AS (

        -- Mode 1: start from a ROLE directly
        SELECT
            P_NAME       AS role_name,
            'MEMBERSHIP' AS privilege
        WHERE UPPER(P_STARTING_POINT_TYPE) = 'ROLE'

        UNION ALL

        -- Mode 2: start from an object – find roles with direct privileges
        SELECT DISTINCT
            grantee_name AS role_name,
            privilege
        FROM snowflake.account_usage.grants_to_roles
        WHERE UPPER(P_STARTING_POINT_TYPE) != 'ROLE'
          AND granted_on    = UPPER(P_STARTING_POINT_TYPE)
          AND name          = P_NAME
          AND (P_DATABASE IS NULL OR table_catalog = P_DATABASE)
          AND (P_SCHEMA   IS NULL OR table_schema  = P_SCHEMA)
          AND deleted_on IS NULL
    ),

    -- Recursively walk the role hierarchy upward.
    -- ROLE_A (has privilege) -> ROLE_B (inherits) -> … -> terminal role
    role_hierarchy (current_role, root_role, privilege, role_path, depth) AS (

        -- Anchor
        SELECT
            role_name,
            role_name,
            privilege,
            role_name,
            1
        FROM base_grants

        UNION ALL

        -- Recursive step: find parent roles that inherit the current role
        SELECT
            rg.parent_role,
            rh.root_role,
            rh.privilege,
            rh.role_path || ' -> ' || rg.parent_role,
            rh.depth + 1
        FROM role_hierarchy rh
        JOIN role_grants rg
            ON rg.child_role = rh.current_role
        WHERE rh.depth < 20                         -- guard against cycles
    )

    -- Final: join to users and deduplicate
    SELECT DISTINCT
        u.grantee_name                                AS user_name,
        UPPER(P_STARTING_POINT_TYPE)                  AS object_type,
        CASE
            WHEN UPPER(P_STARTING_POINT_TYPE) = 'ROLE'
                THEN P_NAME
            ELSE CONCAT_WS('.', P_DATABASE, P_SCHEMA, P_NAME)
        END                                           AS object_fqn,
        rh.privilege,
        rh.root_role                                  AS directly_privileged_role,
        rh.current_role                               AS role_granted_to_user,
        rh.role_path || ' -> ' || u.grantee_name      AS access_path,
        rh.depth + 1                                  AS path_depth
    FROM role_hierarchy rh
    JOIN snowflake.account_usage.grants_to_users u
        ON  u.role       = rh.current_role
        AND u.deleted_on IS NULL
$$
;

--------------------------------------------------------------------------------
-- Usage examples
--------------------------------------------------------------------------------

-- Object mode: all users with any privilege on a specific table
SELECT *
FROM TABLE(get_user_access_paths('TABLE', 'MY_TABLE', 'MY_DB', 'MY_SCHEMA'))
ORDER BY user_name, privilege, path_depth;

-- Object mode: database-level (no schema needed)
SELECT *
FROM TABLE(get_user_access_paths('DATABASE', 'MY_DB'))
ORDER BY user_name, privilege, path_depth;

-- Role mode: all users who hold (directly or via hierarchy) a given role
SELECT *
FROM TABLE(get_user_access_paths('ROLE', 'DATA_ANALYST'))
ORDER BY user_name, path_depth;
