# joschkas-clowd

This repo launches a cloud VM on AWS that runs as a Claude Code workspace. You SSH into it, run Claude Code, and it can autonomously write code, clone repos, create branches and PRs — all from the VM, independent of your local machine.

Shared memory across multiple VM instances is backed by Cloudflare R2, so Claude's notes, skills, and credentials persist even after the VM shuts down.

## What the VM provides

- **Claude Code** — runs interactively on the VM or via browser UI tunneled over SSH; skills, agents, and permission settings are installed automatically on boot
- **GitHub access** — token-based via a fine-grained PAT (`GH_TOKEN` in `.env`); clone/push over HTTPS and open PRs with `gh`. No SSH keys ever land on the VM.
- **Shared persistent memory** — `~/.claude/` is mounted from R2, shared across all instances
- **Environment variables** — your `.env` is synced and sourced automatically in every shell
- **Shared data bucket** — R2 bucket mounted at `/bucket_data`
- **Tools**: `uv`, `gh`, `rclone`, `claude`

## Prerequisites

- [SkyPilot](https://skypilot.readthedocs.io/) installed and configured (`pip install skypilot`)
- AWS credentials configured (`aws configure` or SSO)
- Cloudflare R2 credentials in `~/.cloudflare/r2.credentials` (profile name: `r2`)
- Cloudflare account ID in `~/.cloudflare/accountid`
- SkyPilot R2 check passing: `sky check`

## Setup

### 1. Configure your `.env`

Edit `.env` at the repo root with your secrets (see `.env.example` for the full list):

```env
R2_ACCOUNT_ID="..."
R2_ACCESS_KEY_ID="..."
R2_SECRET_ACCESS_KEY="..."
R2_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com"
HF_TOKEN="..."   # write-scoped: huggingface_hub reads exactly this name
GH_TOKEN="..."   # fine-grained GitHub PAT: Contents + Pull requests read/write on selected repos
```

This file is synced to `~/.env` on the VM and sourced automatically.

### 2. Launch the VM

Pick a hardware profile at launch time:

```bash
CLUSTER="joschkas-" ./launch.sh claude   # Mac-class box for Claude Code (~M4 Pro)   (c8i.4xlarge, 16 vCPU/32 GB, ~$0.75/h)
CLUSTER="joschkas-" ./launch.sh data     # many CPUs + high network for data eng     (any_of list in run.yaml)
CLUSTER="joschkas-" ./launch.sh a10      # A10G GPU for whisper/parakeet etc.        (g5.xlarge, ~$1.01/h)
CLUSTER="joschkas-" ./launch.sh l4       # L4 GPU, 32 vCPU/128 GB, bigger GPU jobs   (g6.8xlarge, ~$2.01/h)
```

AWS regions are restricted to an allowlist — `us-east-1`, `us-east-2`, `us-west-2`, `eu-west-1`, `eu-central-1`, `ap-northeast-2` — defined as the `ordered:` preference list in `src/run.yaml`. It is tried top to bottom, so launches land in `us-east-1` unless the instance type is capacity-constrained there, and can never land outside the six. Passing `--infra` to `sky launch` overrides that list and re-opens every AWS region, so don't.

Extra arguments are passed through to `sky launch` (e.g. `-y`). The cluster name defaults to `joschkas-clowd`; override with `CLUSTER=<name> ./launch.sh ...`. To switch an existing cluster to a different profile, `sky down joschkas-clowd` first — all persistent state lives in R2, not on the VM.

Check the VM:

```bash
sky status joschkas-clowd
```

## Using Claude Code on the VM

### Using tmux (recommended)

Use tmux so your session survives SSH disconnects and you can run multiple panes (e.g. Claude Code + logs side by side).

```bash
sky ssh joschkas-clowd
tmux new -s claude        # start a named session
claude                    # run Claude Code inside it
```

Detach at any time with `Ctrl+B D` — Claude keeps running. Reattach later:

```bash
sky ssh joschkas-clowd
tmux attach -t claude
```

Useful tmux shortcuts:

| Shortcut | Action |
| --- | --- |
| `Ctrl+B D` | Detach (leave session running) |
| `Ctrl+B C` | New window |
| `Ctrl+B %` | Split pane vertically |
| `Ctrl+B "` | Split pane horizontally |
| `Ctrl+B Arrow` | Switch pane |
| `Ctrl+B [` | Scroll mode (use arrow keys, `Q` to exit) |

Setup writes `~/.tmux.conf` on every launch, so every tmux session on the VM has **mouse mode on** (`set -g mouse on`) — scroll with the wheel, click to select panes, drag borders to resize — plus scrollback history persisted to `~/.tmux_history` and new splits/windows inheriting the current pane's cwd.

List all sessions:

```bash
tmux ls
```

### Plain terminal

```bash
sky ssh joschkas-clowd
cd ~/sky_workdir
claude
```

`CLAUDE.md` in the workdir is auto-loaded, so Claude knows about the environment and runs the preflight checks (GitHub token, env vars, AWS SSO) on its own — no copy-paste prompt needed.

**First-time OAuth (once per Claude.ai account):** on the first run, Claude Code prints a login URL. Open it in your local browser (where you're already signed in to claude.ai — Google SSO works as normal), approve, paste the code back. Credentials write to `~/.claude/.credentials.json`, which is R2-backed, so every future VM is pre-authenticated.

### One-click launch from VSCode (Remote Explorer)

Open VSCode directly in `~/sky_workdir` on the VM with:

```bash
./code.sh              # default cluster joschkas-clowd
./code.sh <cluster>    # any other cluster name
```

All integrated terminals on the VM also default to `~/sky_workdir` (Machine-scoped `terminal.integrated.cwd`), so no more `cd` after connecting.

When connected to the VM through the VSCode Remote Explorer plugin, the setup step installs a **Claude** terminal profile. Open the terminal-dropdown chevron next to the `+` in the terminal panel and pick **Claude** — VSCode drops you into a tmux session named `claude` in `~/sky_workdir/` with Claude Code already running. Detach with `Ctrl+B D`; reopen the **Claude** profile to reattach. Other terminal profiles (default **bash**) stay plain shells for `gh`, `git`, logs, etc.

### Browser UI (via SSH tunnel)

In one terminal, open the tunnel:

```bash
sky ssh joschkas-clowd -- -L 8501:localhost:8501 -N
```

In another, start the UI on the VM:

```bash
sky ssh joschkas-clowd
claude --ui --port 8501
```

Open [http://localhost:8501](http://localhost:8501). No ports are exposed publicly — traffic goes over SSH.

### Remote control from claude.ai

VM Claude sessions start with remote control enabled (`remoteControlAtStartup` in `src/claude-settings.json`), so a session running in tmux on the VM can be attached to from claude.ai — handy for checking on long runs from a phone.

## Managing the VM

```bash
sky status                        # list all clusters
sky stop joschkas-clowd           # stop (preserves disk, saves cost)
sky start joschkas-clowd          # restart a stopped cluster
sky down joschkas-clowd           # terminate permanently
```
