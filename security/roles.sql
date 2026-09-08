-- PostgreSQL Production DBA Lab
-- Role definitions
-- Passwords are intentionally excluded from this repository.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'app_readonly'
    ) THEN
        CREATE ROLE app_readonly NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'app_readwrite'
    ) THEN
        CREATE ROLE app_readwrite NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'monitoring_role'
    ) THEN
        CREATE ROLE monitoring_role NOLOGIN;
    END IF;
END
$$;

-- Example login-role assignments:
--
-- CREATE ROLE report_user LOGIN;
-- \password report_user
-- GRANT app_readonly TO report_user;
--
-- CREATE ROLE app_user LOGIN;
-- \password app_user
-- GRANT app_readwrite TO app_user;
