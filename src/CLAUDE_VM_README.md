# VM Environment Guide for Claude

You are running on an AWS EC2 instance managed by SkyPilot. This file tells you everything you need to know to get started.

## Environment Variables

All secrets and config are in `~/.env`, sourced automatically in every shell session.

Available variables:
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` — Cloudflare R2 storage credentials
- `AIC_SDK_LICENSE`, `AIC_LICENSE_KEY` — ai-coustics SDK license
- `HF_API_KEY` — Hugging Face API key

To verify they are loaded:
```bash
echo $R2_ACCOUNT_ID
```

If they are empty, source manually:
```bash
source ~/.env
```

## GitHub Access

Your SSH key is at `~/.ssh/id_rsa` and has access to private GitHub repositories.

Git is configured to use it automatically. To verify:
```bash
ssh -T git@github.com
```

For creating pull requests, `gh` CLI is installed. Authenticate once with:
```bash
gh auth login
```
Choose "GitHub.com" → "SSH" → use existing key at `~/.ssh/id_rsa`.

## Shared Memory

Your `~/.claude/` directory is mounted from the R2 bucket `joschkas-clowd/claude-memory/`. All memory files (`.md`) you write there are shared across all Claude instances and persist after this VM shuts down.

## Installed Tools

- `uv` — fast Python package manager (`~/.local/bin/uv`)
- `gh` — GitHub CLI for PRs and issues
- `rclone` — R2/S3 file sync
- `claude` — Claude Code CLI (`~/.claude/local/claude`)

## Shared Data Bucket

The R2 bucket `joschkas-clowd` is mounted read-write at `/bucket_data`.

## Code Execution Service

A FastAPI service runs on port 8080 serving code execution via MCP. It is started automatically by SkyPilot.

---

## First Prompt

Copy-paste this into Claude Code after launching it (`claude`) to bootstrap your session:

```
Read ~/sky_workdir/CLAUDE_VM_README.md to orient yourself.

You have access to private GitHub repos via SSH (~/.ssh/id_rsa).
Environment variables are in ~/.env and already exported in this shell.
Your memory persists in ~/.claude/ which is shared across all Claude instances via R2.

Before starting any work:
1. Run `ssh -T git@github.com` to confirm GitHub access
2. Run `echo $R2_ACCOUNT_ID` to confirm env vars are loaded
3. Run `gh auth status` to check if gh CLI is authenticated — if not, run `gh auth login`

Then tell me what you'd like to work on.
```
