# Migration Race and Rollback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent false migration failures while S-UI is starting and guarantee a clean rollback with no orphaned listeners or concurrently written files.

**Architecture:** Add a bounded listener-readiness primitive and use it at both health-check boundaries. Reorder rollback into a quiesce, restore, and service-state recovery sequence, with wrapper functions that make timing and process cleanup testable without touching the host.

**Tech Stack:** Bash, systemd, `ss`, `pkill`, the existing shell test harness, Git, Ubuntu VPS.

---

### Task 1: Add failing listener-readiness tests

**Files:**
- Create: `tests/test_lifecycle.sh`
- Modify: `sui-singbox-migrate.sh`

- [ ] **Step 1: Write a test that mocks listener snapshots**

Source the script in library mode, override the listener snapshot and sleep
wrappers, and assert that readiness retries until all four ports appear.

- [ ] **Step 2: Write a timeout test**

Keep one port absent for every iteration and assert that the readiness function
returns failure after the configured number of attempts.

- [ ] **Step 3: Run the lifecycle test**

Run:

```bash
bash tests/test_lifecycle.sh
```

Expected: failure because the readiness helper does not exist yet.

### Task 2: Implement listener readiness

**Files:**
- Modify: `sui-singbox-migrate.sh`
- Test: `tests/test_lifecycle.sh`

- [ ] **Step 1: Add testable wrappers**

Add wrappers for `sleep` and listener snapshots beside the existing curl,
systemctl, and ss wrappers.

- [ ] **Step 2: Implement `wait_for_listeners`**

Check VLESS, VMess, Hysteria2, and TUIC in one retry loop for up to 30 seconds.
Only emit missing-port errors after timeout.

- [ ] **Step 3: Replace snapshot checks**

Use the readiness helper before subscription validation and after the explicit
S-UI restart.

- [ ] **Step 4: Verify the lifecycle test**

Run:

```bash
bash tests/test_lifecycle.sh
```

Expected: listener retry and timeout assertions pass.

### Task 3: Add failing rollback-order tests

**Files:**
- Modify: `tests/test_lifecycle.sh`
- Modify: `sui-singbox-migrate.sh`

- [ ] **Step 1: Record lifecycle operations**

Mock systemctl, residual-process termination, port-release waiting, and backup
copy operations into an ordered event log.

- [ ] **Step 2: Assert quiesce order**

Verify S-UI, sync services, legacy Sing-box, and Argo are stopped before backup
files are copied, and residual processes are terminated before legacy services
are restarted.

- [ ] **Step 3: Run the lifecycle test**

Run:

```bash
bash tests/test_lifecycle.sh
```

Expected: rollback-order assertions fail against the current implementation.

### Task 4: Implement quiescent rollback

**Files:**
- Modify: `sui-singbox-migrate.sh`
- Test: `tests/test_lifecycle.sh`

- [ ] **Step 1: Add residual-process cleanup**

Terminate S-UI and Argo processes by their known executable paths and wait for
panel, subscription, VMess, and node ports to be released.

- [ ] **Step 2: Stop all competing services before file restore**

Disable/stop S-UI and sync units, and stop Sing-box and Argo before removing or
copying directories.

- [ ] **Step 3: Restore service state after files**

Reload systemd only after units and directories are in their final state, then
enable/start the legacy services according to the backup.

- [ ] **Step 4: Verify rollback tests**

Run:

```bash
bash tests/test_lifecycle.sh
```

Expected: all lifecycle assertions pass.

### Task 5: Validate and publish

**Files:**
- Modify: `SHA256SUMS`

- [ ] **Step 1: Run static and automated checks**

```bash
bash -n sui-singbox-migrate.sh tests/*.sh
bash tests/run.sh
shellcheck sui-singbox-migrate.sh tests/test_lifecycle.sh
```

Expected: all tests pass and no actionable shellcheck errors remain.

- [ ] **Step 2: Refresh and verify checksums**

```bash
shasum -a 256 README.md GITHUB-UPLOAD-GUIDE.md s-ui-v1.4.1.sha256 sui-singbox-migrate.sh
shasum -a 256 -c SHA256SUMS
```

Expected: every tracked checksum reports `OK`.

- [ ] **Step 3: Commit and push**

Commit only the spec, plan, script, lifecycle test, and checksum changes, then
push the repository's established `main` workflow to `origin`.

### Task 6: Clean-room VPS verification

**Files:**
- No repository file changes.

- [ ] **Step 1: Remove the failed migration and original node installation**

Stop services, close processes, remove units, commands, configuration,
databases, backups, Nginx setup, and related firewall rules while preserving
SSH and the base operating system.

- [ ] **Step 2: Install upstream eooce Sing-box**

Run the upstream installer non-destructively through its documented interactive
flow and confirm `/etc/sing-box/conf/inbounds.json`, four schemes in
`url.txt`, and all original listeners.

- [ ] **Step 3: Run the migration plan**

Use `DIRECT_PUBLIC_IP=168.93.214.245` and verify the planned ports and four
protocols match the freshly installed source.

- [ ] **Step 4: Run migration**

Use deterministic panel credentials held only on the VPS for automated
verification, and do not print secrets in tool output.

- [ ] **Step 5: Verify end state**

Confirm version, services, six listeners, direct outbound, valid generated
VLESS/VMess/Hysteria2/TUIC links, current IPv4 mapping, VMess CDN mapping, and
zero recent fatal/router errors.

