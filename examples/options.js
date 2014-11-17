#!/usr/bin/higgs --shellscript

var Options = require('lib/options.js').Options;

var o = Options('0.0.12', 'math a b c ... [options]');
o.setArgsRule({min: 2});
o.required('op', "add or mul.");
o.parse(arguments);

var numbers = [];
for (var i = 0; i < o.arguments.length; i++) {
    numbers.push(parseInt(o.arguments[i]));
}

switch (o.parameters.op) {
    case 'add':
        print(numbers.reduce(function (previousValue, currentValue) {
            return previousValue + currentValue;
        }, 0));
        break;
    case 'mul':
        print(numbers.reduce(function (previousValue, currentValue) {
            return previousValue * currentValue;
        }, 1));
        break;
}
