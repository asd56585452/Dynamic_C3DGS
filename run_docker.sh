#!/bin/bash
# ==============================================================================
# Helper script to run commands inside the Dynamic_C3DGS Docker container
# Usage:
#   ./run_docker.sh bash
#   ./run_docker.sh python train.py --config configs/n3d_ours/sear_steak.json ...
# ==============================================================================

set -e

USER_UID=$(id -u)
USER_GID=$(id -g)

if [ $# -eq 0 ]; then
    CMD="bash"
else
    CMD="$@"
fi

env UID=$USER_UID GID=$USER_GID docker compose run --rm dynamic_c3dgs $CMD
