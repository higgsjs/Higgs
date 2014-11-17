// load the tests utilities if they're not present
if (typeof assertEq === 'undefined') {
    require('lib/test.js');
}

var options = require('lib/options.js');

function test_parsing()
{
    var data = options.parse(['foo', 'bar', '--param1', 'val1', 'val2', '--param2', '--param3', 'val3']);

    assertEq(data.arguments[0], 'foo');
    assertEq(data.arguments[1], 'bar');
    assertEqArray(data.parameters.param1, ['val1', 'val2']);
    assertEq(data.parameters.param2, true);
    assertEq(data.parameters.param3, 'val3');
}


function test_errors()
{
    var opt = options.Options("1", "");

    assertEq(undefined, opt._checkArgNumber(2, 2));
    assertTrue(typeof opt._checkArgNumber(2, 3) === 'string');

    assertEq(undefined, opt._checkArgMin(2, 1));
    assertTrue(typeof opt._checkArgNumber(1, 2) === 'string');

    assertEq(undefined, opt._checkArgMax(2, 2));
    assertTrue(typeof opt._checkArgMax(3, 2) === 'string');

    assertEqArray([], opt._checkParamsRequired(["debug", "level", "other"], ["debug", "level"]));
    assertTrue(typeof opt._checkParamsRequired(["debug", "other"], ["debug", "level"])[0] === 'string');

    assertEqArray([], opt._checkParamsUnknown(["debug", "level"], []));
    assertTrue(typeof opt._checkParamsUnknown(["debug", "level"], ["debug", "unknown"])[0] === 'string');
}


test_parsing();
test_errors();
