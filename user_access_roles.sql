--------------------------------------------------------------------------------
-- user_access_roles.sql
--
-- For a given object (table, view, etc.), returns every user who can access it
-- along with every role-hierarchy path from the privileged role to the user,
-- and the depth of each path.
--
-- Uses SNOWFLAKE.ACCOUNT_USAGE views (up to 2-hour latency).
-- Adjust the four SET parameters below before running.
--------------------------------------------------------------------------------

-- ============================================================================
-- Parameters – change these to match your target object
-- ============================================================================
SET object_type     = 'TABLE';        -- TABLE, VIEW, SCHEMA, DATABASE, etc.
SET object_database = 'MY_DB';        -- Database that contains the object
SET object_schema   = 'MY_SCHEMA';    -- Schema that contains the object
                                      -- (set to '' for DATABASE-level objects)
SET object_name     = 'MY_TABLE';     -- Name of the object

-- ============================================================================
-- Query
-- ============================================================================
WITH RECURSIVE

-- Step 1: Find roles that hold direct privileges on the target object
base_grants AS (
    SELECT
        grantee_name  AS role_name,
        privilege
    FROM snowflake.account_usage.grants_to_roles
    WHERE granted_on    = $object_type
      AND table_catalog = $object_database
      AND name          = $object_name
      AND ($object_schema = '' OR table_schema = $object_schema)
      AND deleted_on IS NULL
),

-- Step 2: Recursively walk the role hierarchy upward.
--         If ROLE_A has the privilege and ROLE_B is granted ROLE_A,
--         then ROLE_B inherits the privilege (path: ROLE_A -> ROLE_B).
role_hierarchy (current_role, root_role, privilege, role_path, depth) AS (

    -- Anchor: the roles with direct privileges
    SELECT
        bg.role_name,
        bg.role_name,
        bg.privilege,
        bg.role_name,
        1
    FROM base_grants bg

    UNION ALL

    -- Recursive: find every role that has been granted the current role
    SELECT
        g.grantee_name,
        rh.root_role,
        rh.privilege,
        rh.role_path || ' -> ' || g.grantee_name,
        rh.depth + 1
    FROM role_hierarchy rh
    JOIN snowflake.account_usage.grants_to_roles g
        ON  g.granted_on  = 'ROLE'
        AND g.name        = rh.current_role
        AND g.deleted_on IS NULL
    WHERE rh.depth < 20                       -- safety guard against cycles
)

-- Step 3: Join to users who hold any role in the hierarchy
SELECT
    u.grantee_name                                   AS user_name,
    rh.privilege,
    rh.root_role                                     AS directly_privileged_role,
    rh.current_role                                  AS role_granted_to_user,
    rh.role_path || ' -> ' || u.grantee_name         AS access_path,
    rh.depth + 1                                     AS path_depth
FROM role_hierarchy rh
JOIN snowflake.account_usage.grants_to_users u
    ON  u.role       = rh.current_role
    AND u.deleted_on IS NULL
ORDER BY
    user_name,
    privilege,
    path_depth,
    access_path
;
