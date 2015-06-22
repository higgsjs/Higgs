CUR_DIR=`pwd`
HIGGS_DIR="${CUR_DIR}/source"
DATA_DIR="${CUR_DIR}/data"

echo "Data dir : ${DATA_DIR}"
echo "Higgs dir: ${HIGGS_DIR}"

# Go to the Higgs directory
cd "${HIGGS_DIR}"

echo `pwd`

# FIXME: edit this based on where you put your Truffle v0.5 distribution
echo "You must edit the TRUFFLE_PATH variable"
exit
TRUFFLE_PATH="/home/somebody/something/something/graalvm"

# Copy the benchmarks into the Truffle path
cp -R "${HIGGS_DIR}/benchmarks" "${TRUFFLE_PATH}"
cp "${HIGGS_DIR}/benchmark.py" "${TRUFFLE_PATH}"

# Truffle benchmarking, compilation time excluded (1, 10, 100 warmup iterations)
cd "${TRUFFLE_PATH}"
./benchmark.py --vm_cmd="bin/trufflejs" --bench_list="benchmarks/nocomptime1/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_truffle1.csv"
./benchmark.py --vm_cmd="bin/trufflejs" --bench_list="benchmarks/nocomptime10/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_truffle10.csv"
./benchmark.py --vm_cmd="bin/trufflejs" --bench_list="benchmarks/nocomptime100/benchmark-list.csv" --csv_file="${DATA_DIR}/nocomp_truffle100.csv"

