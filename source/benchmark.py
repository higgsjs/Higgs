#!/usr/bin/env python

from subprocess import *

MAKE_CMD = 'make release'

HIGGS_CMD = './higgs --stats'

NUM_RUNS = 10

BENCHMARKS = [
    'programs/sunspider/3d-cube.js',
    'programs/sunspider/3d-morph.js',
    'programs/sunspider/3d-raytrace.js',
    'programs/sunspider/access-binary-trees.js',
    'programs/sunspider/access-fannkuch.js',  
    'programs/sunspider/access-nbody.js',      
    'programs/sunspider/access-nsieve.js',
    'programs/sunspider/bitops-3bit-bits-in-byte.js',
    'programs/sunspider/bitops-bits-in-byte.js',  
    'programs/sunspider/bitops-bitwise-and.js',       
    'programs/sunspider/bitops-nsieve-bits.js',        
    'programs/sunspider/controlflow-recursive.js',
    'programs/sunspider/crypto-aes.js',     
    'programs/sunspider/crypto-md5.js',
    'programs/sunspider/crypto-sha1.js',
    'programs/sunspider/math-cordic.js',
    'programs/sunspider/math-partial-sums.js',
    'programs/sunspider/math-spectral-norm.js',
    'programs/sunspider/string-fasta.js',

    'programs/v8bench/base.js programs/v8bench/crypto.js programs/v8bench/drv-crypto.js',
    'programs/v8bench/base.js programs/v8bench/deltablue.js programs/v8bench/drv-deltablue.js',
    'programs/v8bench/base.js programs/v8bench/earley-boyer.js programs/v8bench/drv-earley-boyer.js',
    'programs/v8bench/base.js programs/v8bench/navier-stokes.js programs/v8bench/drv-navier-stokes.js',
    'programs/v8bench/base.js programs/v8bench/raytrace.js programs/v8bench/drv-raytrace.js',
    'programs/v8bench/base.js programs/v8bench/richards.js programs/v8bench/drv-richards.js',
]

# Dictionary of string keys to lists of gathered values
values = {}

# Compile Higgs in release mode
call(MAKE_CMD, shell=True)

# For each run
for runNo in range(1, NUM_RUNS+1):

    print "Run #", runNo

    # For each benchmark
    for benchmark in BENCHMARKS:

        print "Benchmark: ", benchmark.split(' ')[-1]

        #pipe = Popen(HIGGS_CMD + ' ' + benchmark, shell=True, stdout=PIPE).stdout
        #output = pipe.readlines()


        # TODO: gather lists of values, one per run, for each string key







