#!/usr/bin/env python

from subprocess import *
import os
import sys
import re
import math
import csv

# Configuration
MAKE_CMD = 'make release'
HIGGS_CMD = './higgs --stats --jit_maxvers=20'
CSV_OUT = 'results.csv'
NUM_RUNS = 1


# TODO: take benchmark cmd as a command-line argument
# Have default argument


# TODO: take csv output file name as an argument





BENCHMARKS = {
    '3d-cube':'programs/sunspider/3d-cube.js',
    '3d-morph':'programs/sunspider/3d-morph.js',
    '3d-raytrace':'programs/sunspider/3d-raytrace.js',
    'binary-trees':'programs/sunspider/access-binary-trees.js',
    'fannkuch':'programs/sunspider/access-fannkuch.js',  
    'nbody':'programs/sunspider/access-nbody.js',      
    'nsieve':'programs/sunspider/access-nsieve.js',
    '3bit':'programs/sunspider/bitops-3bit-bits-in-byte.js',
    'bits-in-byte':'programs/sunspider/bitops-bits-in-byte.js',  
    'bitwise-and':'programs/sunspider/bitops-bitwise-and.js',       
    'nsieve-bits':'programs/sunspider/bitops-nsieve-bits.js',        
    'recursive':'programs/sunspider/controlflow-recursive.js',
    'crypto-aes':'programs/sunspider/crypto-aes.js',     
    'crypto-md5':'programs/sunspider/crypto-md5.js',
    'crypto-sha1':'programs/sunspider/crypto-sha1.js',
    'cordic':'programs/sunspider/math-cordic.js',
    'partial-sums':'programs/sunspider/math-partial-sums.js',
    'spectral-norm':'programs/sunspider/math-spectral-norm.js',
    'fasta':'programs/sunspider/string-fasta.js',

    'v8-crypto':'programs/v8bench/base.js programs/v8bench/crypto.js programs/v8bench/drv-crypto.js',
    'deltablue':'programs/v8bench/base.js programs/v8bench/deltablue.js programs/v8bench/drv-deltablue.js',
    'earley-boyer':'programs/v8bench/base.js programs/v8bench/earley-boyer.js programs/v8bench/drv-earley-boyer.js',
    'navier-stokes':'programs/v8bench/base.js programs/v8bench/navier-stokes.js programs/v8bench/drv-navier-stokes.js',
    'v8-raytrace':'programs/v8bench/base.js programs/v8bench/raytrace.js programs/v8bench/drv-raytrace.js',
    'richards':'programs/v8bench/base.js programs/v8bench/richards.js programs/v8bench/drv-richards.js',
}

# Per-benchmark results
benchResults = {}

# Compile Higgs in release mode
call(MAKE_CMD, shell=True)

# Captured value pattern
valPattern = re.compile('^([^:]+):([^:]+)$')

# For each benchmark
benchNo = 1
for benchmark in BENCHMARKS:

    benchFiles = BENCHMARKS[benchmark]
    print '%s (%d / %d)' % (benchmark, benchNo, len(BENCHMARKS))
    benchNo += 1

    # Dictionary of string keys to lists of gathered values
    valLists = {}

    # For each run
    for runNo in range(1, NUM_RUNS+1):

        print 'Run #%d / %d' % (runNo, NUM_RUNS)

        # Run the benchmark and capture its output
        pipe = Popen(HIGGS_CMD + ' ' + benchFiles, shell=True, stdout=PIPE).stdout
        output = pipe.readlines()

        #print output

        # For each line of output
        for line in output:

            match = valPattern.match(line)

            # If the line doesn't match, continue
            if match == None or len(line) > 50:
                continue

            key = match.group(1)
            val = float(match.group(2))

            # Add the value to the list for this key
            if not (key in valLists):
                valLists[key] = []
            valLists[key] = valLists[key] + [val]

    # Store the values for this benchmark
    benchResults[benchmark] = valLists

# Computes the geometric mean of a list of values
def geoMean(numList):
    prod = 1
    for val in numList:
        prod *= val
    return prod ** (1.0/len(numList))

# Compute the geometric mean of values
benchMeans = {}
for benchmark, valLists in benchResults.items():
    valMeans = {}
    for key, valList in valLists.items():
        valMeans[key] = geoMean(valList)
    benchMeans[benchmark] = valMeans

# Output the mean execution times for all benchmarks
print ''
print 'exec times'
print '----------'
for benchmark, valMeans in benchMeans.items():
    print benchmark + ":", valMeans['exec time (ms)']

# Output the mean of all stats gathered
print ''
print 'mean values'
print '-----------'
valLists = {}
for benchmark, valMeans in benchMeans.items():
    for key, mean in valMeans.items():
        if not (key in valLists):
            valLists[key] = []
        valLists[key] += [mean]
for key, valList in valLists.items():
    print key + ':', int(geoMean(valList))

# TODO
# Produce CSV output
outFile = open(CSV_OUT, 'w')
writer = csv.writer(outFile, delimiter=' ', quotechar='"', quoting=csv.QUOTE_MINIMAL)
#writer.writerow(['Spam', 'Lovely Spam', 'Wonderful Spam'])








