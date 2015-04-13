var options = require('lib/options');
var console = require('lib/console');

options
    // set version number
    .setVersion('1.0.0')
    // set the usage string
    .setUsage('file1, file2, fileN')
    // long option only
    .add('long', null, null, 'long option.')
    // long and short option
    .add('double', null, null, 'long and short option', 'd')
    // short option only
    .add(null, null, null, 'short option.', 's')
    //    long    defult  type          description         short   required
    .add('param', 13.37, '+float', 'a positive float value', 'p', true);

// alternate construction
// var o = Options({
//     version: '1.0.0',
//     usage: 'file1, file2, fileN',
//     opts: [
//         {long: 'long', desc: 'long option'},
//         {long: 'double', short: 'd', desc: 'long and short option'},
//         {short: 's', desc: 'short option'},
//         {long: 'param', defval: 13.37, type: '+float', desc: 'a positive float value', short: 'p', req: true},
//     ],
// });

// Values are converted and added to the result object.
// Both the long and short option will contain the value.
// The plain arguments are placed in an array that
// can be accessed via the _ property on the result.
var r = options.parse(arguments);

// display the resulting object
console.log(r);
