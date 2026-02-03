/*
 * pgsentinel_poll_ash_data.sql
 * 
 *   This script creates the infrastructure for incremental polling of PostgreSQL
 *   Active Session History (ASH) data using the pgsentinel extension. It enables
 *   efficient collection of session activity metrics over time without duplicating
 *   previously captured data. The function runs as SECURITY DEFINER with a dedicated
 *   'pgsentinel' role that has minimal required privileges.
 * 
 *   The script implements the pgsentinel_poll_ash_data(slot) function, which uses a
 *   slot-based system (0-99) to support multiple parallel collectors. Each slot employs
 *   advisory locks to prevent concurrent execution and tracks the last poll time via
 *   filesystem persistence in data_directory/__pgsentinel_slot_N files. The function
 *   returns incremental ASH data from pg_active_session_history since the last poll.
 *   Filesystem persistence is required for this approach to work correctly on hot
 *   standby clusters. Slot identifiers are numeric as a simple way to prevent SQL
 *   injection concerns.
 * 
 * Usage:
 *   SELECT * FROM pgsentinel_poll_ash_data(10);  -- Poll using slot 10
 */

-- the COPY command requires pg_write_server_files
-- the pg_read_file() command requires SECURITY DEFINER, and creating this function as superuser

-- Clean up any existing function and role from previous runs
DROP FUNCTION IF EXISTS pgsentinel_poll_ash_data(INT);

-- Revoke function ACL (not role memberships - those auto-cleanup)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pgsentinel') THEN
    REVOKE EXECUTE ON FUNCTION pg_read_file(text) FROM pgsentinel;
  END IF;
END
$$;

DROP ROLE IF EXISTS pgsentinel;

-- Create the dedicated role with minimal privileges
-- Note: INHERIT is required for SECURITY DEFINER functions to access privileges from granted roles
CREATE ROLE pgsentinel NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOLOGIN NOREPLICATION NOBYPASSRLS PASSWORD NULL;
GRANT pg_write_server_files TO pgsentinel;
GRANT pg_read_all_settings TO pgsentinel;
GRANT EXECUTE ON FUNCTION pg_read_file(text) TO pgsentinel;

-- Create function as superuser, then transfer ownership
CREATE OR REPLACE FUNCTION pgsentinel_poll_ash_data(p_slot INT)
RETURNS TABLE(
    ash_time TIMESTAMP WITH TIME ZONE
  , datid OID
  , datname TEXT
  , pid INTEGER
  , leader_pid INTEGER
  , usesysid OID
  , usename TEXT
  , application_name TEXT
  , client_addr TEXT
  , client_hostname TEXT
  , client_port INTEGER
  , backend_start TIMESTAMP WITH TIME ZONE
  , xact_start TIMESTAMP WITH TIME ZONE
  , query_start TIMESTAMP WITH TIME ZONE
  , state_change TIMESTAMP WITH TIME ZONE
  , wait_event_type TEXT
  , wait_event TEXT
  , state TEXT
  , backend_xid XID
  , backend_xmin XID
  , top_level_query TEXT
  , query TEXT
  , cmdtype TEXT
  , queryid BIGINT
  , backend_type TEXT
  , blockers INTEGER
  , blockerpid INTEGER
  , blocker_state TEXT
  , sample_count NUMERIC
) AS $$
DECLARE
  v_last_poll_time TIMESTAMP;
  v_current_poll_time TIMESTAMP;
  v_filepath TEXT;
BEGIN
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 99 THEN
    RAISE EXCEPTION 'slot must be an integer between 0 and 99';
  END IF;

  -- Use advisory lock to prevent concurrent execution for the same slot
  -- Lock key: combine a namespace constant with the slot number
  -- Using hashtext('pgsentinel_poll_ash_data') as namespace to avoid conflicts
  IF NOT pg_try_advisory_xact_lock((1845936723::bigint << 32) | p_slot::bigint) THEN
    RAISE EXCEPTION 'Another instance is already running for slot %. Aborting to prevent concurrent execution.', p_slot;
  END IF;

  v_filepath := current_setting('data_directory') || '/__pgsentinel_slot_' || p_slot::text;

  BEGIN
    SELECT pg_read_file(v_filepath)::timestamp INTO v_last_poll_time;
  EXCEPTION
    WHEN undefined_file THEN
      RAISE WARNING 'UNDEFINED_FILE (58P01) reading file % - expected on first run; will attempt to create', v_filepath;
  END;

  -- Capture current time before writing to avoid race condition
  v_current_poll_time := now();
  EXECUTE format('COPY (SELECT %L::text) TO %L', v_current_poll_time, v_filepath);

  RETURN QUERY
    SELECT 
      ash.*
      -- sample_count: Expected number of samples during the polling window
      -- This is very difficult to accurately calculate for two reasons:
      --   1) Using timestamps of actual samples can be skewed if samples at the beginning
      --      or end of the period did not collect data simply because the system was idle
      --   2) Using begin/end poll times is difficult in cases where pgsentinel_ash.sampling_period
      --      does not evenly divide into the number of seconds between calls to this function
      -- We choose the latter approach (using poll times) as the best option after considering
      -- tradeoffs. This should usually be accurate with small sampling periods.
      ,(ROUND(EXTRACT(EPOCH FROM v_current_poll_time) - EXTRACT(EPOCH FROM coalesce(v_last_poll_time, v_current_poll_time - interval '1 second'))) / current_setting('pgsentinel_ash.sampling_period')::numeric)::numeric as sample_count
    FROM pg_active_session_history ash
    WHERE ash.ash_time > coalesce(v_last_poll_time, '1980-01-01'::timestamp)
      AND ash.ash_time <= v_current_poll_time;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = pg_catalog, public, pg_temp
;

-- Transfer ownership so function executes with pgsentinel privileges
ALTER FUNCTION pgsentinel_poll_ash_data(INT) OWNER TO pgsentinel;

-- Grant execution to PUBLIC since pg_active_session_history is already accessible to PUBLIC
GRANT EXECUTE ON FUNCTION pgsentinel_poll_ash_data(INT) TO PUBLIC;

CREATE EXTENSION IF NOT EXISTS pgsentinel;
