#!/usr/bin/env python

from subprocess import *
import os
import sys
import re
import math
import csv
from optparse import OptionParser

# Configuration
MAKE_CMD = 'make release'
DEF_NUM_RUNS = 1
DEF_HIGGS_CMD = './higgs --stats --jit_maxvers=20'
DEF_CSV_FILE = ''

# Parse the command-line options
parser = OptionParser()
parser.add_option("--csv_file", default=DEF_CSV_FILE)
parser.add_option("--higgs_cmd", default=DEF_HIGGS_CMD)
parser.add_option("--num_runs", type="int", default=DEF_NUM_RUNS)
(options, args) = parser.parse_args()

# Benchmark programs
BENCHMARKS = {
    '3d-cube':'programs/sunspider/3d-cube.js',
    '3d-morph':'programs/sunspider/3d-morph.js',
    '3d-raytrace':'programs/sunspider/3d-raytrace.js',
    'binary-trees':'programs/sunspider/access-binary-trees.js',
    'fannkuch':'programs/sunspider/access-fannkuch.js',  
    'nbody':'programs/sunspider/access-nbody.js',      
    'nsieve':'programs/sunspider/access-nsieve.js',
    '3bits-byte':'programs/sunspider/bitops-3bit-bits-in-byte.js',
    'bits-in-byte':'programs/sunspider/bitops-bits-in-byte.js',  
    'bitwise-and':'programs/sunspider/bitops-bitwise-and.js',       
    'nsieve-bits':'programs/sunspider/bitops-nsieve-bits.js',        
    'recursive':'programs/sunspider/controlflow-recursive.js',

    # Bug in regexp lib? disable for now
    #'crypto-aes':'programs/sunspider/crypto-aes.js',

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

print "higgs cmd:", options.higgs_cmd
print "num runs :", options.num_runs
print ''

# For each benchmark
benchNo = 1
for benchmark in BENCHMARKS:

    benchFiles = BENCHMARKS[benchmark]
    print '%s (%d / %d)' % (benchmark, benchNo, len(BENCHMARKS))
    benchNo += 1

    # Dictionary of string keys to lists of gathered values
    valLists = {}

    # For each run
    for runNo in range(1, options.num_runs + 1):

        print 'Run #%d / %d' % (runNo, options.num_runs)

        # Run the benchmark and capture its output
        pipe = Popen(options.higgs_cmd + ' ' + benchFiles, shell=True, stdout=PIPE).stdout
        output = pipe.readlines()

        #print output

        # For each line of output
        for line in output:

            # If this line contains the string "error" or "exception", abort
            if line.lower().find("error") != -1 or line.lower().find("exception") != -1:
                raise Exception(line)

            match = valPattern.match(line)

            # If the line doesn't match, continue
            if match == None:
                continue

            # Try extracting a key and value
            try:
                key = match.group(1)
                val = float(match.group(2))
            except:
                continue

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
        if val != 0:
            prod *= val
    return prod ** (1.0/len(numList))

# Check if all the values in a list are integer
def valsInt(numList):
    for val in numList:
        if val != int(val):
            return False
    return True

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
    mean = geoMean(valList)
    if valsInt(valList):
        print "%s: %s" % (key, int(mean))
    else:
        print "%s: %.1f" % (key, mean)

# Produce CSV output
if options.csv_file != '':
    print ''
    print 'writing csv output to "%s"' % (options.csv_file)
    outFile = open(options.csv_file, 'w')
    writer = csv.writer(outFile, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
    keys = valLists.keys()
    writer.writerow([''] + keys)
    for benchmark, valMeans in benchMeans.items():
        values = []
        for key in keys:
            mean = valMeans[key]
            if int(mean) == mean:
                mean = int(mean)
            values += [mean]
        writer.writerow([benchmark] + values)

