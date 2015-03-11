if (typeof assertEq === 'undefined')
{
    require('lib/test.js');
}

var options = require('lib/options.js');

function test_parseArgv()
{
    var argv = ['arg1', '--longbool', '--longval=val', '-abc', 'arg2', '-def=val'];

    var p = options._parseArgv(argv);

    assertEqArray(p.args, ['arg1', 'arg2']);

    assert(p.opts.longbool);
    assertEq(p.opts.longval, 'val');
    assert(p.opts.a);
    assert(p.opts.b);
    assert(p.opts.c);
    assert(p.opts.d);
    assert(p.opts.e);
    assertEq(p.opts.f, 'val');
}

function test_parse_result()
{
    var o = options.Options()
        .add('long', null)
        .add('double', null, null, null, 'd')
        .add(null, null, 'boolean', null, 's');

    var r = o.parse(['--long=val1', '-sd=val2', 'arg1', 'arg2', 'arg3']);

    assertEqArray(r._, ['arg1', 'arg2', 'arg3']);
    assertEq(r.long, 'val1');
    assertEq(r.d, 'val2');
    assertEq(r.double, 'val2');
    assert(r.s);
}

function test_parse_defval()
{
    var o = options.Options()
        .add('default', 'qwerty', null, null, 'D');

    var r = o.parse([]);

    assertEq(r.default, 'qwerty');
    assertEq(r.D, 'qwerty');
}

function test_parse_convert()
{
    var o = options.Options()
        .add('intval', null, 'int')
        .add('floatval', null, 'float')
        .add('yes', null, 'boolean')
        .add('off', null, 'boolean')
        .add('false', null, 'boolean')
        .add('one', null, 'boolean');

    var r = o.parse(['--intval=3', '--floatval=0.5', '--yes=yes', '--off=off', '--false=false', '--one=1']);

    assertEq(r.intval, 3);
    assertEq(r.floatval, 0.5);
    assert(r.yes);
    assert(!r.off);
    assert(!r.false);
}

function test_testFloat()
{
    assert(options._testFloat('-33'));
    assert(options._testFloat('33.'));
    assert(options._testFloat('-.33'));
    assert(options._testFloat('33.33'));
    assert(!options._testFloat(''));
    assert(!options._testFloat('.'));
    assert(!options._testFloat('-.'));
}

function test_testFloatPositive()
{
    assert(options._testFloatPositive('33'));
    assert(options._testFloatPositive('33.'));
    assert(options._testFloatPositive('.33'));
    assert(options._testFloatPositive('33.33'));
    assert(!options._testFloatPositive(''));
    assert(!options._testFloatPositive('.'));
    assert(!options._testFloatPositive('-33.33'));
}

function test_testInt()
{
    assert(options._testInt('33'));
    assert(options._testInt('-33'));
    assert(!options._testInt('abc'));
}

function test_testIntPositive()
{
    assert(options._testIntPositive('33'));
    assert(!options._testIntPositive('-33'));
    assert(!options._testIntPositive('abc'));
}

function test_testBoolean()
{
    assert(options._testBoolean(true));
    assert(options._testBoolean(false));
    assert(options._testBoolean('on'));
    assert(options._testBoolean('off'));
    assert(options._testBoolean('1'));
    assert(options._testBoolean('0'));
    assert(options._testBoolean('yes'));
    assert(options._testBoolean('no'));
    assert(options._testBoolean('true'));
    assert(options._testBoolean('false'));
    assert(!options._testBoolean('this isnt boolean'));
}

function test_convertValue()
{
    assertEq(options._convertValue('3.14', 'float'), 3.14);
    assertEq(options._convertValue('-3.14', 'float'), -3.14);
    assertEq(options._convertValue('3.14', '+float'), 3.14);
    assertEq(options._convertValue('3', 'int'), 3);
    assertEq(options._convertValue('-3', 'int'), -3);
    assertEq(options._convertValue('3', '+int'), 3);
    assertEq(options._convertValue(true, 'boolean'), true);
    assertEq(options._convertValue('1', 'boolean'), true);
    assertEq(options._convertValue('on', 'boolean'), true);
    assertEq(options._convertValue('yes', 'boolean'), true);
    assertEq(options._convertValue('true', 'boolean'), true);
    assertEq(options._convertValue(false, 'boolean'), false);
    assertEq(options._convertValue('0', 'boolean'), false);
    assertEq(options._convertValue('off', 'boolean'), false);
    assertEq(options._convertValue('no', 'boolean'), false);
    assertEq(options._convertValue('false', 'boolean'), false);
}

test_parseArgv();
test_parse_result();
test_parse_defval();
test_parse_convert();
test_testFloat();
test_testFloatPositive();
test_testInt();
test_testIntPositive();
test_testBoolean();
test_convertValue();
