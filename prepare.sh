#!/bin/bash

set -euo pipefail

exec start.sh jupyter lab ${JUPYTERLAB_ARGS}
