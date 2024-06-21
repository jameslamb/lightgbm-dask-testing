#!/bin/bash

# [description]
#
#     Profile memory usage of all of LightGBM's Python examples, using memray.

set -e -u -o pipefail

echo "profiling examples"
mkdir -p "${PROFILING_OUTPUT_DIR}/bin"

# shellcheck disable=SC2044
for py_script in $(find "${LIGHTGBM_HOME}/examples/python-guide" -name '*.py'); do
    base_filename=$(basename "${py_script}")
    prof_file="${base_filename/.py/.bin}"
    table_file="${base_filename/.py/-table.html}"
    leak_table_file="${base_filename/.py/-leak-table.html}"
    flamegraph_file="${base_filename/.py/-flamegraph.html}"
    echo "  - ${base_filename}"
    memray run \
        -o "${PROFILING_OUTPUT_DIR}/bin/${prof_file}" \
        "${py_script}" > /dev/null 2>&1 ||
        true
    memray table \
        -o "${PROFILING_OUTPUT_DIR}/${table_file}" \
        --force \
        "${PROFILING_OUTPUT_DIR}/bin/${prof_file}"
    memray table \
        -o "${PROFILING_OUTPUT_DIR}/${leak_table_file}" \
        --force \
        --leaks \
        "${PROFILING_OUTPUT_DIR}/bin/${prof_file}"
    memray flamegraph \
        -o "${PROFILING_OUTPUT_DIR}/${flamegraph_file}" \
        --force \
        "${PROFILING_OUTPUT_DIR}/bin/${prof_file}"
done
echo "Done profiling examples. See '${PROFILING_OUTPUT_DIR}' for results."
