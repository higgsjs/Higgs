//println('hi!');

load('tests/load/loadee.js');

//println(_loadeeVar_);

assert (
    _loadeeVar_ === 0x1337c0d3,
    'load file failed'
);

