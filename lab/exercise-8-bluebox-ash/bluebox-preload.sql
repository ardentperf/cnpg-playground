-- bluebox-preload.sql
--
-- Creates the roles and database that bluebox expects, before restoring the
-- pg_dump. Run this against the postgres database as superuser BEFORE the
-- pg_dump | psql restore step.
--
-- The roles mirror what bluebox's 01-create-roles-and-database.sql creates
-- inside its own container. Using --no-owner --no-acl on the restore means
-- everything will be owned and accessible by the postgres superuser, which is
-- fine for a lab environment.
--

-- Non-login group roles
CREATE ROLE bluebox_admin;
CREATE ROLE bluebox_app;

-- Login users
CREATE USER bb_admin WITH PASSWORD 'admin_password';
GRANT bluebox_admin TO bb_admin;

CREATE USER bb_app WITH PASSWORD 'app_password';
GRANT bluebox_app TO bb_app;

-- Database
CREATE DATABASE bluebox;
GRANT ALL ON DATABASE bluebox TO bluebox_admin;
GRANT CONNECT ON DATABASE bluebox TO bluebox_app;
