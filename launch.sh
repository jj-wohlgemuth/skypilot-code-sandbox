#!/usr/bin/env bash
# Launch the VM with a hardware profile:
#   ./launch.sh claude   Mac-class box for Claude Code (~M4 Pro)       (c8i.4xlarge, 16 vCPU/32 GB, ~$0.75/h)
#   ./launch.sh data     many CPUs + high network for data engineering (ordered list in run.yaml)
#   ./launch.sh a10      A10G for whisper/parakeet etc.                (g5.xlarge,   ~$1.01/h)
#   ./launch.sh l4       L4 + 32 vCPU/128 GB for bigger GPU jobs       (g6.8xlarge,  ~$2.01/h)
#   ./launch.sh l40s     L40S 48 GB VRAM, 8 vCPU/64 GB                 (g6e.2xlarge, ~$2.24/h)
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
  data)   OVERRIDES=() ;;  # uses the ordered list in run.yaml
  # NOTE: no custom --image-id here. SkyPilot's default AWS GPU image is
  # Ubuntu-based with NVIDIA drivers; the once-suggested DLAMI
  # ami-0f4d5ef8f66860703 is Amazon Linux 2023, which breaks the apt-based
  # setup script in run.yaml (no claude, no ~/.claude, nothing).
  # No --infra here, on purpose: it would override the per-region entries in
  # run.yaml's `ordered` list and re-open every AWS region. The allowlist there
  # is what lets a GPU launch fail over when a type is capacity-constrained
  # (g6.8xlarge regularly is in us-east-1). Cheapest allowed region wins, which
  # is normally us-east-1; /bucket_data is R2 and region-agnostic, but S3 reads
  # from another region are cross-region egress and are billed as such.
  a10)    OVERRIDES=(--instance-type g5.xlarge --gpus A10G:1) ;;
  l4)     OVERRIDES=(--instance-type g6.8xlarge --gpus L4:1) ;;
  l40s)   OVERRIDES=(--instance-type g6e.2xlarge --gpus L40S:1) ;;
  *) echo "usage: $0 {claude|data|a10|l4|l40s} [extra sky launch args]" >&2; exit 1 ;;
esac

# ${arr[@]+...} guard: bash 3.2 (macOS default) errors on empty-array
# expansion under `set -u`, which hits the `data` profile (no overrides).
exec sky launch -c "$CLUSTER" src/run.yaml ${OVERRIDES[@]+"${OVERRIDES[@]}"} "$@"
