this.foo = function () { return 1; }

assert (foo() === 1);

this.foo = function () { return 2; }

assert (foo() === 2);

