var OLD_PRINT = print;
var console = require('lib/console');

function expectedOutput(exp_str, msg)
{
    print = function(str)
    {
        assertEq(str, exp_str, msg);
    }
}

expectedOutput("5");
console.log(5);

expectedOutput("5");
console.log(5.0);

expectedOutput("5.5");
console.log(5.5);

expectedOutput("false");
console.log(false);

expectedOutput("null");
console.log(null);

expectedOutput("undefined");
console.log(undefined);

expectedOutput("{  }");
console.log({});

expectedOutput("[ 1, 2, 3 ]");
console.log([1,2,3]);

expectedOutput("foo");
console.log("foo");

expectedOutput("foo\tfoo");
console.log("foo", "foo");

expectedOutput("works");
console.log({toString: function(){ return "works"; }});

expectedOutput("{ foo : 'bar' }");
console.log({ foo: "bar"});

var x = Object.create(null);
x.bar = 5;
expectedOutput("{ bar : 5 }");
console.log(x);

var f = { foo : x };
x.baz = f;

// FIXME: can't assume enumeration order for for-in!
//expectedOutput("{ bar : 5, baz : { foo : {...} } }");
//console.log(x);

print = OLD_PRINT;
