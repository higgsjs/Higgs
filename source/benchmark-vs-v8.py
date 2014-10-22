#!/usr/bin/env python

from subprocess import *
import os
import math
import csv

# Read a CSV file into a list of rows
def readCSV(fileName):

    inFile = open(fileName, 'r')
    reader = csv.reader(inFile, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)

    rows = []
    for row in reader:
        rows += [row]

    inFile.close()

    return rows

# Grab a column by index or name string
def grabCol(tbl, index, newName=None):

    # If the index is a column name
    if isinstance(index, str):
        row0 = tbl[0]
        for idx,name in enumerate(row0):
            if name == index:
                index = idx
                break
        if isinstance(index, str):
            raise Exception("name not found: \"%s\"" % index)

    # Extract the first column
    newTbl = []
    for row in tbl:
        row = row[index:index+1]
        newTbl += [row]

    # If a new column name was specified
    if newName:
        newTbl[0][0] = newName

    return newTbl

# Computes the geometric mean of a list of values
def geoMean(numList):
    prod = 1
    for val in numList:
        if val != 0:
            prod *= val
    return prod ** (1.0/len(numList))

# Compute the geometric mean of all values in a table
def tblMean(tbl):

    numList = []

    for row in tbl:
        for cell in row:
            try:
                numList += [float(cell)]
            except:
                pass

    return geoMean(numList)

# Generate relative numbers from absolute number columns
def genRelTbl(valTbl, defTbl):

    newTbl = []

    for rowIdx, row in enumerate(valTbl):

        newRow = []

        for cellIdx, cell in enumerate(row):

            try:
                val = float(cell)
                defV = float(defTbl[rowIdx][cellIdx])
                rel = 100 * val / defV
                newRow += [rel]
            except:
                newRow += [cell]

        newTbl += [newRow]

    return newTbl

os.system('./benchmark.py --vm_cmd="~/Dropbox/Linux/bin/d8 --nocrankshaft" --bench_list=benchmarks/nocomptime/benchmark-list.csv --csv_file="v8-base.csv"')
os.system('./benchmark.py --vm_cmd="~/Dropbox/Linux/bin/d8" --bench_list=benchmarks/nocomptime/benchmark-list.csv --csv_file="v8-crank.csv"')
os.system('./benchmark.py --vm_cmd="./higgs" --bench_list=benchmarks/nocomptime/benchmark-list.csv --csv_file="higgs.csv"')

base_results  = readCSV("v8-base.csv")
crank_results = readCSV("v8-crank.csv")
higgs_results = readCSV("higgs.csv")

os.system('rm v8-base.csv')
os.system('rm v8-crank.csv')
os.system('rm higgs.csv')

base_times  = grabCol(base_results, 'exec time (ms)')
crank_times = grabCol(crank_results, 'exec time (ms)')
higgs_times = grabCol(higgs_results, 'exec time (ms)')

ratio_base  = genRelTbl(higgs_times, base_times)
ratio_crank = genRelTbl(higgs_times, crank_times)

mean_base = tblMean(ratio_base)
mean_crank = tblMean(ratio_crank)

print "baseline ratio: ", mean_base
print "crankshaft ratio: ", mean_crank




