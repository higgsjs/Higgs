#!/usr/bin/env python

from subprocess import *
import os
import sys
import time
import re
import math
import csv
from optparse import OptionParser

# Configuration
MAKE_CMD = 'make release'
DEF_NUM_RUNS = 1
DEF_VM_CMD = './higgs --stats'
DEF_BENCH_LIST = 'benchmark-list.csv'
DEF_CSV_FILE = ''

# Parse the command-line options
parser = OptionParser()
parser.add_option("--csv_file", default=DEF_CSV_FILE)
parser.add_option("--vm_cmd", default=DEF_VM_CMD)
parser.add_option("--bench_list", default=DEF_BENCH_LIST)
parser.add_option("--num_runs", type="int", default=DEF_NUM_RUNS)
(options, args) = parser.parse_args()

# Load the benchmark file list
benchmarks = {}
csvFile = open(options.bench_list, 'rb')
csvReader = csv.reader(csvFile, delimiter=',', quotechar='"')
for row in csvReader:
    if len(row) == 0:
        continue
    benchName = row[0]
    benchFiles = row[1:]
    benchmarks[benchName] = benchFiles

# Per-benchmark results
benchResults = {}

# If benchmarking Higgs, compile Higgs in release mode
if "higgs" in options.vm_cmd:
    call(MAKE_CMD, shell=True)

# Captured value pattern
valPattern = re.compile('^([^:]+):([^:]+)$')

print "vm cmd:", options.vm_cmd
print "benchmark list:", options.bench_list
print "num benchmarks:", len(benchmarks)
print "num runs:", options.num_runs
print ''

totalTimeStart = time.time()

# For each benchmark
benchNo = 1
for benchmark in benchmarks:

    print '%s (%d / %d)' % (benchmark, benchNo, len(benchmarks))
    benchNo += 1

    # Dictionary of string keys to lists of gathered values
    valLists = {}

    # Add an entry for the wall clock time
    valLists['wall time (ms)'] = []

    benchFiles = ' '.join(benchmarks[benchmark])
    benchCmd = options.vm_cmd + ' ' + benchFiles

    # For each run
    for runNo in range(1, options.num_runs + 1):

        print 'Run #%d / %d' % (runNo, options.num_runs)

        wallTimeStart = time.time()

        # Run the benchmark and capture its output
        pipe = Popen(benchCmd, shell=True, stdout=PIPE)

        # Wait until the benchmark terminates
        pipe.wait()

        wallTimeEnd = time.time()

        # Verify the return code
        ret = pipe.returncode
        if ret != 0:
            raise Exception('invalid return code: ' + str(ret))

        # Add an value for the wall clock time
        wallTime = int(round(1000 * (wallTimeEnd - wallTimeStart)))
        valLists['wall time (ms)'] = valLists['wall time (ms)'] + [wallTime]

        # Read the output
        output = pipe.stdout.readlines()

        # For each line of output
        for line in output:

            # If this line contains the string "error" or "exception", abort
            if line.lower().find("error") != -1 or \
               line.lower().find("exception") != -1 or \
               line.lower().find("segmentation fault") != -1:
                raise Exception(line)

            # If the line doesn't match, continue
            match = valPattern.match(line)
            if match == None:
                continue

            # Try extracting a key and value
            try:
                key = match.group(1)
                val = float(match.group(2))
            except:
                continue

            assert (key != 'wall time (ms)')

            # Add the value to the list for this key
            if not (key in valLists):
                valLists[key] = []
            valLists[key] = valLists[key] + [val]

    # Store the values for this benchmark
    benchResults[benchmark] = valLists

totalTimeEnd = time.time()

# Computes the geometric mean of a list of values
def geoMean(numList):
    if len(numList) == 1:
        return numList[0]

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
for benchmark in sorted(benchMeans.keys()):
    valMeans = benchMeans[benchmark]
    if 'exec time (ms)' in valMeans:
        print benchmark + ":", valMeans['exec time (ms)']
    else:
        print benchmark + " (wtc):", valMeans['wall time (ms)']

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

for key in sorted(valLists.keys()):
    valList = valLists[key]
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
    keys = sorted(valLists.keys())
    writer.writerow([''] + keys)
    for benchmark, valMeans in benchMeans.items():
        values = []
        for key in keys:
            if not key in valMeans:
                mean = 0
            else:
                mean = valMeans[key]
            if int(mean) == mean:
                mean = int(mean)
            values += [mean]
        writer.writerow([benchmark] + values)

print ''
print 'total benchmarking time: %.1f s' % (totalTimeEnd - totalTimeStart)

