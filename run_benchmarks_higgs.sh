CUR_DIR=`pwd`
HIGGS_DIR="${CUR_DIR}/source"
DATA_DIR="${CUR_DIR}/data"

echo "Data dir : ${DATA_DIR}"
echo "Higgs dir: ${HIGGS_DIR}"

# Go to the Higgs directory
cd "${HIGGS_DIR}"

echo `pwd`

# Perf stats (used for code size, compilation time)
./benchmark.py --num_runs=10 --vm_cmd="./higgs --perf_stats --shape_novers --maxvers=0" --csv_file="${DATA_DIR}/perf_maxvers0.csv"
./benchmark.py --num_runs=10 --vm_cmd="./higgs --perf_stats --shape_novers --maxvers=1" --csv_file="${DATA_DIR}/perf_maxvers1.csv"
./benchmark.py --num_runs=10 --vm_cmd="./higgs --perf_stats --shape_novers --maxvers=5" --csv_file="${DATA_DIR}/perf_maxvers5.csv"
./benchmark.py --num_runs=10 --vm_cmd="./higgs --perf_stats --shape_novers --maxvers=100" --csv_file="${DATA_DIR}/perf_maxvers100.csv"

# Execution time stats with compilation time excluded
./benchmark.py --vm_cmd="./higgs --shape_novers --maxvers=0" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/time_maxvers0.csv"
./benchmark.py --vm_cmd="./higgs --shape_novers --maxvers=1" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/time_maxvers1.csv"
./benchmark.py --vm_cmd="./higgs --shape_novers --maxvers=5" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/time_maxvers5.csv"
./benchmark.py --vm_cmd="./higgs --shape_novers --maxvers=100" --bench_list="benchmarks/nocomptime/benchmark-list.csv" --csv_file="${DATA_DIR}/time_maxvers100.csv"

# Full stats (used for version counts)
./benchmark.py --vm_cmd="./higgs --stats --shape_novers --maxvers=0" --csv_file="${DATA_DIR}/maxvers0.csv"
./benchmark.py --vm_cmd="./higgs --stats --shape_novers --maxvers=1" --csv_file="${DATA_DIR}/maxvers1.csv"
./benchmark.py --vm_cmd="./higgs --stats --shape_novers --maxvers=5" --csv_file="${DATA_DIR}/maxvers5.csv"
./benchmark.py --vm_cmd="./higgs --stats --shape_novers --maxvers=100" --csv_file="${DATA_DIR}/maxvers100.csv"

# Higgs benchmarking, compilation time excluded (1, 10, 100 warmup iterations)
./benchmark.py --vm_cmd="./higgs --shape_novers" --bench_list="benchmarks/nocomptime1/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_higgs1.csv"
./benchmark.py --vm_cmd="./higgs --shape_novers" --bench_list="benchmarks/nocomptime10/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_higgs10.csv"
./benchmark.py --vm_cmd="./higgs --shape_novers" --bench_list="benchmarks/nocomptime100/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_higgs100.csv"

