CUR_DIR=`pwd`
HIGGS_DIR="${CUR_DIR}/source"
DATA_DIR="${CUR_DIR}/data"

echo "Data dir : ${DATA_DIR}"
echo "Higgs dir: ${HIGGS_DIR}"

# Go to the Higgs directory
cd "${HIGGS_DIR}"

echo `pwd`

# Comparative performance with TraceMonkey, compilation time excluded
./benchmark.py --vm_cmd="${CUR_DIR}/bin/js -j" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_tm.csv"

