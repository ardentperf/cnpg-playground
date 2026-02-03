-- Sanitize SQL function to remove sensitive data from query texts
-- For more information, see: https://ardentperf.com/2025/10/15/sanitized-sql/

CREATE OR REPLACE FUNCTION sanitize_sql(sql_text text) 
RETURNS text AS $$
DECLARE
    cleaned_text text;
    -- Regex to match up to three identifiers
    -- cf. https://www.postgresql.org/docs/current/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
    first_part_regex_3words text := '([[:alnum:]_$()]+)[^[:alnum:]_$()]+([[:alnum:]_$()]+)[^[:alnum:]_$()]+([[:alnum:]_$()]+)';
    first_part_regex_2words text := '([[:alnum:]_$()]+)[^[:alnum:]_$()]+([[:alnum:]_$()]+)';
    first_part_regex_1words text := '([[:alnum:]_$()]+)';
    first_part text;
    match_array text;
    from_parts_regex_3words text := '(FROM)[^[:alnum:]_$()]+([[:alnum:]_$()]+)[^[:alnum:]_$()]*([[:alnum:]_$()]*)';
    from_parts text := '';
BEGIN
    -- Remove multi-line comments (/* ... */)
    cleaned_text := regexp_replace(sql_text, '/\*.*?\*/', '', 'g');
    
    -- Remove single-line comments (-- to end of line)
    cleaned_text := regexp_replace(cleaned_text, '--.*?(\n|$)', '', 'g');
    
    -- Extract the first keyword and up to two words after it
    first_part := array_to_string(regexp_match(cleaned_text,first_part_regex_3words),' ');
    if first_part is null or first_part ILIKE '% FROM %' or first_part ILIKE '% FROM' then
      first_part := array_to_string(regexp_match(cleaned_text,first_part_regex_2words),' ');
      if first_part is null or first_part ILIKE '% FROM' then
        first_part := array_to_string(regexp_match(cleaned_text,first_part_regex_1words),' ');
      end if;
    end if;
    first_part := regexp_replace(first_part, '\(.*','(...)');
    
    -- Find all occurrences of FROM and two words after each
    FOR match_array IN 
        SELECT array_to_string(regexp_matches(cleaned_text,from_parts_regex_3words,'gi'),' ') 
    LOOP
        match_array := regexp_replace(match_array, '\(.*','(...)');
        from_parts := from_parts || '...' || match_array;
    END LOOP;
    
    -- Return combined result
    RETURN first_part || from_parts;
END;
$$ LANGUAGE plpgsql;