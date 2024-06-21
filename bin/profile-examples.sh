#!/bin/bash

# [description]
#
#     Profile all of LightGBM's Python examples, using cProfile.

set -e -u -o pipefail

echo "profiling examples"
# shellcheck disable=SC2044
for py_script in $(find "${LIGHTGBM_HOME}/examples/python-guide" -name '*.py'); do
    base_filename=$(basename "${py_script}")
    prof_file="${base_filename/.py/.prof}"
    echo "  - ${base_filename}"
    python \
        -Wignore \
        -m cProfile \
        -o "${PROFILING_OUTPUT_DIR}/${prof_file}" \
        "${py_script}" > /dev/null 2>&1 ||
        true
done
echo "Done profiling examples. See '${PROFILING_OUTPUT_DIR}' for results."
