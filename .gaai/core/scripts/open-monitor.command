#!/bin/bash
# Operator convenience wrapper (double-clickable on macOS). It invokes the daemon
# lifecycle through the PRIVILEGED EXECUTABLE ENTRY — never `bash <script>`, which
# daemon-start.sh refuses because a non-privileged interpreter has already applied
# BASH_ENV and imported exported functions before the script's first instruction.
cd "$(dirname "$0")/../../.." && exec .gaai/core/scripts/daemon-start.sh --monitor
