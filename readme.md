#PostgreSQL Unit Testing Framework (plpgunit)

Plpgunit started out of curiosity on why a unit testing framework cannot be simple and easy to use?

# Documentation

<table>
  <tr>
    <th>
      Function
    </th>
    <th>
      Usage
    </th>
  </tr>
  <tr>
    <td>
      assert.fail(text)
    </td>
    <td>
      Fails a test.
    </td>
  </tr>
  <tr>
    <td>
      assert.ok(text)
    </td>
    <td>
      Should be placed at the end of a test function's body to propose that the test passed.
    </td>
  </tr>
  <tr>
    <td>
      assert.is_equal(IN have anyelement, IN want anyelement, OUT message text, OUT result boolean)
    </td>
    <td>
      Fails the test if the first two arguments do not match.
    </td>
  </tr>
  <tr>
    <td>
      assert.is_not_equal(IN already_have anyelement, IN dont_want anyelement, OUT message text, OUT result boolean)
    </td>
    <td>
      Fails the test if the first two argument match.
    </td>
  </tr>
</table>

# Creating a Plpgunit Unit Test 

A unit test is a function which : 
* must be created under the schema "unit_tests".
* should not have any arguments.
* should always return "test_result" data type.

The following query invokes all unit tests that have been created under the schema "unit_tests":

	BEGIN TRANSACTION;
	SELECT * FROM unit_tests.begin();
	ROLLBACK TRANSACTION;

## Example #1

	DROP FUNCTION IF EXISTS unit_tests.example1();

	CREATE FUNCTION unit_tests.example1()
	RETURNS test_result
	AS
	$$
	DECLARE message test_result;
	BEGIN
		IF 1 = 1 THEN
			SELECT assert.fail('This failed intentionally.') INTO message;
			RETURN message;
		END IF;

		SELECT assert.ok('End of test.') INTO message;	
		RETURN message;	
	END
	$$
	LANGUAGE plpgsql;

	BEGIN TRANSACTION;
	SELECT * FROM unit_tests.begin();
	ROLLBACK TRANSACTION;

**Will Result In**

	Test completed on : 2013-10-18 19:30:01.543 UTC. 
	Total test runtime: 19 ms.

	Total tests run : 1.
	Passed tests    : 0.
	Failed tests    : 1.

	List of failed tests:
	-----------------------------
	unit_tests.example1() --> This failed intentionally.

## Example #2

	CREATE FUNCTION unit_tests.example2()
	RETURNS test_result
	AS
	$$
	DECLARE message test_result;
	DECLARE result boolean;
	DECLARE have integer;
	DECLARE want integer;
	BEGIN
		want := 100;
		SELECT 50 + 49 INTO have;

		SELECT * FROM assert.is_equal(have, want) INTO message, result;

		--Test failed.
		IF result = false THEN
			RETURN message;
		END IF;
		
		--Test passed.
		SELECT assert.ok('End of test.') INTO message;	
		RETURN message;	
	END
	$$
	LANGUAGE plpgsql;

	BEGIN TRANSACTION;
	SELECT * FROM unit_tests.begin();
	ROLLBACK TRANSACTION;

**Will Result In**

	Test completed on : 2013-10-18 19:47:11.886 UTC. 
	Total test runtime: 21 ms.

	Total tests run : 2.
	Passed tests    : 0.
	Failed tests    : 2.

	List of failed tests:
	-----------------------------
	unit_tests.example1() --> This failed intentionally.
	unit_tests.example2() --> ASSERT IS_EQUAL FAILED.

	Have -> 99
	Want -> 100

## Example 3

	DROP FUNCTION IF EXISTS unit_tests.example3();

	CREATE FUNCTION unit_tests.example3()
	RETURNS test_result
	AS
	$$
	DECLARE message test_result;
	DECLARE result boolean;
	DECLARE have integer;
	DECLARE dont_want integer;
	BEGIN
		dont_want := 100;
		SELECT 50 + 49 INTO have;

		SELECT * FROM assert.is_not_equal(have, dont_want) INTO message, result;

		--Test failed.
		IF result = false THEN
			RETURN message;
		END IF;
		
		--Test passed.
		SELECT assert.ok('End of test.') INTO message;	
		RETURN message;	
	END
	$$
	LANGUAGE plpgsql;

	BEGIN TRANSACTION;
	SELECT * FROM unit_tests.begin();
	ROLLBACK TRANSACTION;

**Will Result In**

	Test completed on : 2013-10-18 19:48:30.578 UTC. 
	Total test runtime: 11 ms.

	Total tests run : 3.
	Passed tests    : 1.
	Failed tests    : 2.

	List of failed tests:
	-----------------------------
	unit_tests.example1() --> This failed intentionally.
	unit_tests.example2() --> ASSERT IS_EQUAL FAILED.

	Have -> 99
	Want -> 100


Happy testing!