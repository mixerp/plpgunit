/********************************************************************************
Copyright (C) Binod Nepal, Mix Open Foundation (http://mixof.org).

This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. 
If a copy of the MPL was not distributed  with this file, You can obtain one at 
http://mozilla.org/MPL/2.0/.
***********************************************************************************/

DROP SCHEMA IF EXISTS assert CASCADE;
DROP SCHEMA IF EXISTS unit_tests CASCADE;
DROP DOMAIN IF EXISTS test_result CASCADE;

CREATE SCHEMA assert AUTHORIZATION postgres;
CREATE SCHEMA unit_tests AUTHORIZATION postgres;
CREATE DOMAIN test_result AS text;

CREATE TABLE unit_tests.tests
(
	test_id				SERIAL NOT NULL PRIMARY KEY,
	started_on			TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
	completed_on		TIMESTAMP WITHOUT TIME ZONE NULL,
	total_tests			integer NULL DEFAULT(0),
	failed_tests		integer NULL DEFAULT(0)
);

CREATE INDEX unit_tests_tests_started_on_inx
ON unit_tests.tests(started_on);

CREATE INDEX unit_tests_tests_completed_on_inx
ON unit_tests.tests(completed_on);

CREATE INDEX unit_tests_tests_failed_tests_inx
ON unit_tests.tests(failed_tests);

CREATE TABLE unit_tests.test_details
(
	id					BIGSERIAL NOT NULL PRIMARY KEY,
	test_id				integer NOT NULL REFERENCES unit_tests.tests(test_id),
	function_name		text NOT NULL,
	message				text NOT NULL,
	ts					TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT(CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
	status				boolean NOT NULL
);

CREATE INDEX unit_tests_test_details_test_id_inx
ON unit_tests.test_details(test_id);

CREATE INDEX unit_tests_test_details_status_inx
ON unit_tests.test_details(status);

CREATE FUNCTION assert.fail(message text)
RETURNS text
AS
$$
BEGIN
	IF $1 IS NULL OR trim($1) = '' THEN
		message := 'NO REASON SPECIFIED';
	END IF;
	
	RAISE WARNING 'ASSERT FAILED : %', message;
	RETURN message;
END
$$
LANGUAGE plpgsql
IMMUTABLE STRICT;

CREATE FUNCTION assert.ok(message text)
RETURNS text
AS
$$
BEGIN
	RAISE NOTICE 'OK : %', message;
	RETURN '';
END
$$
LANGUAGE plpgsql
IMMUTABLE STRICT;

CREATE FUNCTION assert.is_equal(IN have anyelement, IN want anyelement, OUT message text, OUT result boolean)
AS
$$
BEGIN
	IF($1 = $2) THEN
		message := 'Assert is equal.';
		PERFORM assert.ok(message);
		result := true;
		RETURN;
	END IF;

	message := E'ASSERT IS_EQUAL FAILED.\n\nHave -> ' || $1::text || E'\nWant -> ' || $2::text || E'\n'; 	
	PERFORM assert.fail(message);
	result := false;
	RETURN;
END
$$
LANGUAGE plpgsql
IMMUTABLE STRICT;

CREATE FUNCTION assert.is_not_equal(IN already_have anyelement, IN dont_want anyelement, OUT message text, OUT result boolean)
AS
$$
BEGIN
	IF($1 != $2) THEN
		message := 'Assert is not equal.';
		PERFORM assert.ok(message);
		result := true;
		RETURN;
	END IF;
	
	message := E'ASSERT IS_NOT_EQUAL FAILED.\n\nAlready Have -> ' || $1::text || E'\nDon''t Want   -> ' || $2::text || E'\n'; 	
	PERFORM assert.fail(message);
	result := false;
	RETURN;
END
$$
LANGUAGE plpgsql
IMMUTABLE STRICT;

CREATE FUNCTION assert.function_exists(function_name text, OUT message text, OUT result boolean)
AS
$$
BEGIN
	IF NOT EXISTS
	(
		SELECT  1
		FROM    pg_catalog.pg_namespace n
		JOIN    pg_catalog.pg_proc p
		ON      pronamespace = n.oid
		WHERE replace(nspname || '.' || proname || '(' || oidvectortypes(proargtypes) || ')', ' ' , '')::text=$1
	) THEN
		message := 'The function % does not exist.', $1;
		PERFORM assert.fail(message);

		result := false;
		RETURN;
	END IF;

	message := 'OK. The function ' || $1 || ' exists.';
	PERFORM assert.ok(message);
	result := true;
	RETURN;
END
$$
LANGUAGE plpgsql;

CREATE FUNCTION unit_tests.begin()
RETURNS TABLE(message text, result character(1))
AS
$$
	DECLARE this record;
	DECLARE _function_name text;
	DECLARE _sql text;
	DECLARE _message text;
	DECLARE _result character(1);
	DECLARE _test_id integer;
	DECLARE _status boolean;
	DECLARE _total_tests integer = 0;
	DECLARE _failed_tests integer = 0;
	DECLARE _list_of_failed_tests text;
	DECLARE _started_from TIMESTAMP WITHOUT TIME ZONE;
	DECLARE _completed_on TIMESTAMP WITHOUT TIME ZONE;
	DECLARE _delta integer;
	DECLARE _ret_val text = '';
BEGIN
	_started_from := clock_timestamp() AT TIME ZONE 'UTC';

	SELECT nextval('unit_tests.tests_test_id_seq') INTO _test_id;

	INSERT INTO unit_tests.tests(test_id)
	SELECT _test_id;

	FOR this IN
		SELECT proname as function_name
		FROM    pg_catalog.pg_namespace n
		JOIN    pg_catalog.pg_proc p
		ON      pronamespace = n.oid
		WHERE   nspname = 'unit_tests'
		AND prorettype='test_result'::regtype::oid
	LOOP
		_status := false;
		_total_tests := _total_tests + 1;
		
		_function_name = 'unit_tests.' || this.function_name || '()';
		_sql := 'SELECT ' || _function_name || ';';
		
		RAISE NOTICE 'RUNNING TEST : %.', _function_name;

		EXECUTE _sql INTO _message;

		IF _message = '' THEN
			_status := true;
		END IF;

		
		INSERT INTO unit_tests.test_details(test_id, function_name, message, status)
		SELECT _test_id, _function_name, _message, _status;

		IF NOT _status THEN
			_failed_tests := _failed_tests + 1;			
			RAISE WARNING 'TEST % FAILED.', _function_name;
			RAISE WARNING 'REASON: %', _message;
		ELSE
			RAISE NOTICE 'TEST % COMPLETED WITHOUT ERRORS.', _function_name;
		END IF;
	END LOOP;

	_completed_on := clock_timestamp() AT TIME ZONE 'UTC';
	_delta := extract(millisecond from _completed_on - _started_from)::integer;
	
	UPDATE unit_tests.tests
	SET total_tests = _total_tests, failed_tests = _failed_tests, completed_on = _completed_on
	WHERE test_id = _test_id;

	SELECT array_to_string(array_agg(unit_tests.test_details.function_name || ' --> ' || unit_tests.test_details.message), E'\n') INTO _list_of_failed_tests 
	FROM unit_tests.test_details 
	WHERE test_id = _test_id
	AND status= false;

	_ret_val := _ret_val ||  'Test completed on : ' || _completed_on || E' UTC. \nTotal test runtime: ' || _delta || E' ms.\n';
	_ret_val := _ret_val || E'\nTotal tests run : ' || COALESCE(_total_tests, '0');
	_ret_val := _ret_val || E'.\nPassed tests    : ' || COALESCE(_total_tests, '0') - COALESCE(_failed_tests, '0');
	_ret_val := _ret_val || E'.\nFailed tests    : ' || COALESCE(_failed_tests, '0');
	_ret_val := _ret_val || E'.\n\nList of failed tests:\n' || '-----------------------------';
	_ret_val := _ret_val || E'\n' || COALESCE(_list_of_failed_tests, '<NULL>');
	_ret_val := _ret_val || E'\n\n';

	IF _failed_tests > 0 THEN
		_result := 'N';
		RAISE WARNING '%', _ret_val;
	ELSE
		_result := 'Y';
		RAISE NOTICE '%', _ret_val;	
	END IF;

	RETURN QUERY SELECT _ret_val, _result;
END
$$
LANGUAGE plpgsql;
