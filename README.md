# joschkas-clowd

This repo lets you launch a cloud VM on AWS that runs as a Claude Code workspace. You SSH into it, run Claude Code, and it can autonomously write code, clone repos, create branches and PRs — all from the VM, independent of your local machine.

The VM also runs a code execution API (MCP server) so your local Claude Desktop or VS Code can send code to be executed remotely in a Docker sandbox.

Shared memory across multiple VM instances is backed by Cloudflare R2, so Claude's notes and context persist even after the VM shuts down.

## What the VM provides

- **Claude Code** — runs interactively on the VM or via browser UI tunneled over SSH
- **GitHub access** — your `~/.ssh/id_rsa` is synced to the VM; clone, push, and open PRs with `gh`
- **Shared persistent memory** — `~/.claude/` is mounted from R2, shared across all instances
- **Environment variables** — your `.env` is synced and sourced automatically in every shell
- **Code execution API** — FastAPI server on port 8080, usable as an MCP tool from local Claude clients
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

Edit `.env` at the repo root with your secrets:

```env
R2_ACCOUNT_ID="..."
R2_ACCESS_KEY_ID="..."
R2_SECRET_ACCESS_KEY="..."
R2_ENDPOINT="https://<account_id>.r2.cloudflarestorage.com"
HF_API_KEY="..."
```

This file is synced to `~/.env` on the VM and sourced automatically.

### 2. Set your auth token

The code execution API requires a token. Set it in your shell:

```bash
export AUTH_TOKEN=<a-random-string-you-choose>
```

### 3. Launch the VM

```bash
sky launch -c vf2-benchmark src/run.yaml --env AUTH_TOKEN=$AUTH_TOKEN
```

SkyPilot will provision an x86 AWS instance in `us-east-1`, sync your files, and start the API server.

Check the VM IP:

```bash
sky status joschkas-clowd
```

## Using Claude Code on the VM

### Terminal (interactive) 1

```bash
sky ssh joschkas-clowd
```


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

List all sessions:

```bash
tmux ls
```

### Terminal (interactive) 2

On first login, authenticate the `gh` CLI:

```bash
gh auth login
# Choose: GitHub.com → SSH → use existing key ~/.ssh/id_rsa
```

Then start Claude Code:

```bash
claude
```

Paste this first prompt to bootstrap Claude's awareness of the environment:

```text
Read ~/sky_workdir/CLAUDE_VM_README.md to orient yourself.

You have access to private GitHub repos via SSH (~/.ssh/id_rsa).
Environment variables are in ~/.env and already exported in this shell.
Your memory persists in ~/.claude/ which is shared across all Claude instances via R2.

Before starting any work:
1. Run `aws sso login --profile=default` to authenticate against AWS via SSO
2. Run `ssh -T git@github.com` to confirm GitHub access
3. Run `echo $R2_ACCOUNT_ID` to confirm env vars are loaded
4. Run `gh auth status` to check if gh CLI is authenticated — if not, run `gh auth login`

Then tell me what you'd like to work on.
```

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

## Using the Code Execution API (MCP)

The VM runs a sandboxed code execution service on port 8080. Your local Claude Desktop or VS Code can use it as an MCP tool.

Get the VM's public IP from `sky status joschkas-clowd`, then configure your MCP client:

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "code-execution-server": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/alex000kim/skypilot-code-sandbox.git",
        "mcp-server"
      ],
      "env": {
        "API_BASE_URL": "http://<VM_IP>:8080",
        "AUTH_TOKEN": "<YOUR_AUTH_TOKEN>"
      }
    }
  }
}
```

**VS Code** (`.vscode/mcp.json`): same config, rename `mcpServers` to `servers`.

Test the endpoint:

```bash
curl http://<VM_IP>:8080/health -H "Authorization: Bearer $AUTH_TOKEN"
```

## Managing the VM

```bash
sky status                        # list all clusters
sky stop joschkas-clowd           # stop (preserves disk, saves cost)
sky start joschkas-clowd          # restart a stopped cluster
sky down joschkas-clowd           # terminate permanently
```

## Local Development

```bash
pip install -e .
python -m uvicorn src.api:app --host 0.0.0.0 --workers 4 --port 8080
```

Set `"API_BASE_URL": "http://localhost:8080"` in your MCP config for local testing.
