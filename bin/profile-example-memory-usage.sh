#!/bin/bash

# [description]
#
#     Profile memory usage of all of LightGBM's Python examples, using memray.

set -e -u -o pipefail

echo "profiling examples"
mkdir -p "${PROFILING_OUTPUT_DIR}"
for py_script in $(find "${LIGHTGBM_HOME}/examples/python-guide" -name '*.py'); do
    base_filename=$(basename "${py_script}")
    prof_file=$(echo "${base_filename}" | sed -e 's/\.py/\.bin/g')
    table_file=$(echo "${base_filename}" | sed -e 's/\.py/-table\.html/g')
    leak_table_file=$(echo "${base_filename}" | sed -e 's/\.py/-leak-table\.html/g')
    flamegraph_file=$(echo "${base_filename}" | sed -e 's/\.py/-flamegraph\.html/g')
    echo "  - ${base_filename}"
    memray run \
        -o "${PROFILING_OUTPUT_DIR}/bin/${prof_file}" \
        "${py_script}" 2>&1 > /dev/null \
    || true
    memray table \
        -o "${PROFILING_OUTPUT_DIR}/bin/${table_file}" \
        --force \
        "${PROFILING_OUTPUT_DIR}/${prof_file}"
    memray table \
        -o "${PROFILING_OUTPUT_DIR}/bin/${leak_table_file}" \
        --force \
        --leaks \
        "${PROFILING_OUTPUT_DIR}/bin/${prof_file}"
    memray flamegraph \
        -o "${PROFILING_OUTPUT_DIR}/bin/${flamegraph_file}" \
        --force \
        "${PROFILING_OUTPUT_DIR}/${prof_file}"
done
echo "Done profiling examples. See '${PROFILING_OUTPUT_DIR}' for results."
