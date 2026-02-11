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
 * TODO: need a way to know if we're overflowing the ring buffer. this happens easily.
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
      /*
       * Calculating Sample Counts with pgsentinel
       * ------------------------------------------
       *
       * sample_count: Expected number of samples during the polling window
       *
       * This is very difficult to accurately calculate for two reasons:
       *   1) Using timestamps of actual samples can be skewed if samples at the beginning
       *      or end of the period did not collect data simply because the system was idle
       *   2) Using begin/end poll times is difficult in cases where pgsentinel_ash.sampling_period
       *      does not evenly divide into the number of seconds between calls to this function
       *
       * We choose the latter approach (using poll times) as the best option after considering
       * tradeoffs. This should usually be accurate with small sampling periods.
       *
       * pgsentinel collects samples at a regular interval; typically every 1 second,
       * but configurable to other values like 5, 10, or 15 seconds. The sampling
       * period is always a whole number of seconds (never fractional). Separately,
       * a polling process periodically retrieves the latest batch of samples. The
       * key constraint is that we must never count the same sample twice.
       *
       * Suppose our polling window starts at 1:00:05.128 and ends at 1:01:07.704.
       * The elapsed time is approximately 62.576 seconds.
       *
       * To calculate how many sampling attempts occurred during this window, we
       * apply FLOOR only to the numerator (elapsed seconds):
       *
       *   FLOOR(EXTRACT(EPOCH FROM v_current_poll_time) - EXTRACT(EPOCH FROM v_last_poll_time))
       *     / current_setting('pgsentinel_ash.sampling_period')::numeric
       *
       * With a 1-second sampling period:
       *   - Numerator: FLOOR(62.576) → 62
       *   - Denominator: 1
       *   - sample_count = 62 / 1 = 62
       *
       * We use FLOOR on the numerator to count only fully completed seconds in the
       * polling window, avoiding any partial second at the end. We are not guaranteed
       * that pgsentinel always operates exactly on time, but dropping partial seconds
       * is a reasonable compromise. We intentionally leave the division result as-is 
       * (potentially fractional) because the sampling period might not evenly divide 
       * into the elapsed seconds between polls.
       *
       * With a 5-second sampling period:
       *   - Numerator: FLOOR(62.576) → 62
       *   - Denominator: 5
       *   - sample_count = 62 / 5 = 12.4
       *
       * This fractional result (12.4) is a reasonable compromise. The actual number
       * of samples recorded may be 12 or 13, depending on exactly when samples were
       * taken relative to the polling window boundaries:
       *
       * Polling window starting at 1:00:05.128 and ending at 1:01:07.704:
       *   - Example A (samples at offsets 06, 11, 16, 21, 26, 31, 36, 41, 46, 51,
       *                56, 01, 06): 13 samples
       *   - Example B (samples at offsets 09, 14, 19, 24, 29, 34, 39, 44, 49, 54,
       *                59, 04): 12 samples
       *
       * We have no data telling us exactly when sample attempts occurred;we only
       * know the polling window boundaries and timestamps for any non-idle samples
       * that were actually recorded. So returning a fractional sample count is a
       * practical compromise that averages out over time. With the most common
       * sampling period of 1 second, we would not see fractional sample counts.
       *
       * Why this matters for metrics:
       *
       *   For calculating average active sessions, we divide the number of observed
       *   active samples by the sample count. For example, if we observed activity
       *   in 30 samples out of 62 attempts, our average active sessions is
       *   30 / 62 ≈ 0.48.
       *
       * Why FLOOR instead of ROUND?
       *
       *   Using FLOOR ensures we never overcount by rounding up to include a
       *   partially completed interval. This produces more conservative, predictable
       *   counts—especially important when these values feed into utilization or
       *   activity metrics. ROUND would occasionally overstate sample counts, which
       *   could skew averages.
       */
      ,(FLOOR(EXTRACT(EPOCH FROM v_current_poll_time) - EXTRACT(EPOCH FROM coalesce(v_last_poll_time, v_current_poll_time - interval '1 second'))) / current_setting('pgsentinel_ash.sampling_period')::numeric)::numeric as sample_count
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
