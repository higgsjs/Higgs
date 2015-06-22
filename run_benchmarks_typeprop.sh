# NOTE: the type propagation analysis requires several gigabytes of RAM to run.
# It may fail on systems with insufficient memory.

CUR_DIR=`pwd`
HIGGS_DIR="${CUR_DIR}/source"
DATA_DIR="${CUR_DIR}/data"

echo "Data dir : ${DATA_DIR}"
echo "Higgs dir: ${HIGGS_DIR}"

# Go to the Higgs directory
cd "${HIGGS_DIR}"

echo `pwd`

# Perf stats (used for code size, compilation time)
./benchmark.py --num_runs=10 --vm_cmd="./higgs --perf_stats --shape_novers --maxvers=0 --typeprop" --csv_file="${DATA_DIR}/perf_typeprop.csv"

# Execution time stats with compilation time excluded
./benchmark.py --vm_cmd="./higgs --shape_novers --maxvers=0 --typeprop" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/time_typeprop.csv"

# Full stats (used for version counts)
./benchmark.py --vm_cmd="./higgs --stats --shape_novers --maxvers=0 --typeprop" --csv_file="${DATA_DIR}/typeprop.csv"

