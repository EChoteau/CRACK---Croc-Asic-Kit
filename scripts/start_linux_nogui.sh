#!/bin/sh
# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Use the user's runtime directory when available.
# Fall back to a per-user directory under /tmp for headless environments.

RUNDIR=${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}
mkdir -p "$RUNDIR"

# Ensure that the Docker image used by the development environment is up to date.

env UID=$(id -u) GID=$(id -g) docker compose pull pulp-docker
# Start an interactive, disposable PULP Docker environment.
# The host UID/GID prevents root-owned files in mounted directories.
# PS1 identifies the container as "osic" and displays the working directory.
# XDG_RUNTIME_DIR is shared for tools that require a runtime directory.

env UID=$(id -u) GID=$(id -g) docker compose run --rm \
  -e PS1="\[\033[01;32m\]osic:\[\033[00m\]\[\033[01;34m\]\w\[\033[00m\] $" \
  -e XDG_RUNTIME_DIR=$RUNDIR \
  -v "$RUNDIR:$RUNDIR" \
  pulp-docker
