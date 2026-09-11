#!/usr/bin/env bash
# Launch the VM with a hardware profile:
#   ./launch.sh claude   Mac-class box for Claude Code (~M4 Pro)       (c8i.4xlarge, 16 vCPU/32 GB, ~$0.75/h)
#   ./launch.sh data     many CPUs + high network for data engineering (any_of list in run.yaml)
#   ./launch.sh a10      A10G for whisper/parakeet etc.                (g5.xlarge,   ~$1.01/h)
#   ./launch.sh l4       L4 + 32 vCPU/128 GB for bigger GPU jobs       (g6.8xlarge,  ~$2.01/h)
#
# Extra args are passed through to `sky launch` (e.g. -y, --use-spot).
# Cluster name defaults to joschkas-clowd; override with CLUSTER=<name>.
#
# NOTE: switching profile means switching hardware — `sky down $CLUSTER` first
# (or launch under a different CLUSTER name). All state that matters lives in
# R2 (~/.claude, /bucket_data); ~/sky_workdir is ephemeral anyway.
set -euo pipefail

PROFILE=${1:-}
[ $# -gt 0 ] && shift
CLUSTER=${CLUSTER:-joschkas-clowd}

case "$PROFILE" in
  claude) OVERRIDES=(--instance-type c8i.4xlarge) ;;
  data)   OVERRIDES=() ;;  # uses the any_of list in run.yaml
  # NOTE: no custom --image-id here. SkyPilot's default AWS GPU image is
  # Ubuntu-based with NVIDIA drivers; the once-suggested DLAMI
  # ami-0f4d5ef8f66860703 is Amazon Linux 2023, which breaks the apt-based
  # setup script in run.yaml (no claude, no ~/.claude, nothing).
  # `--infra aws` overrides run.yaml's `region: us-east-1` pin so SkyPilot can
  # fail over to another region when a GPU type is capacity-constrained there
  # (g6.8xlarge regularly is). The optimizer still picks the cheapest region
  # first, which is us-east-1. /bucket_data is R2, so it is region-agnostic;
  # S3 reads from another region still work but cross-region egress is billed.
  a10)    OVERRIDES=(--instance-type g5.xlarge --gpus A10G:1 --infra aws) ;;
  l4)     OVERRIDES=(--instance-type g6.8xlarge --gpus L4:1 --infra aws) ;;
  *) echo "usage: $0 {claude|data|a10|l4} [extra sky launch args]" >&2; exit 1 ;;
esac

# ${arr[@]+...} guard: bash 3.2 (macOS default) errors on empty-array
# expansion under `set -u`, which hits the `data` profile (no overrides).
exec sky launch -c "$CLUSTER" src/run.yaml ${OVERRIDES[@]+"${OVERRIDES[@]}"} "$@"
