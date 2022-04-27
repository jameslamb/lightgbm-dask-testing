#!/bin/bash

# [description]
#
#     Profile all of LightGBM's Python examples, using cProfile.

set -e -u -o pipefail

echo "profiling examples"
for py_script in $(find "${LIGHTGBM_HOME}/examples/python-guide" -name '*.py'); do
    base_filename=$(basename "${py_script}")
    prof_file=$(echo "${base_filename}" | sed -e 's/\.py/\.prof/g')
    echo "  - ${base_filename}"
    python \
        -Wignore \
        -m cProfile \
        -o "${PROFILING_OUTPUT_DIR}/${prof_file}" \
        "${py_script}" 2>&1 > /dev/null \
    || true
done
echo "Done profiling examples. See '${PROFILING_OUTPUT_DIR}' for results."
