# Prefer IPv4 for Direct Nodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make VLESS-Reality, Hysteria2, and TUIC prefer the VPS public IPv4 while leaving VMess-Argo on its CDN endpoint.

**Architecture:** Add one IPv4 validation/detection boundary in the source-loading phase. Apply the resolved address only to direct protocols; retain the existing per-protocol source address as a safe fallback.

**Tech Stack:** Bash, curl, jq, shellcheck, shell-based tests.

---

### Task 1: Specify address selection with failing tests

**Files:**
- Modify: `tests/test_source_parser.sh`
- Modify: `tests/test_payloads.sh`

- [x] Add assertions that a configured `DIRECT_PUBLIC_IP` replaces the three direct protocol addresses.
- [x] Add an assertion that VMess remains on `cdns.doon.eu.org`.
- [x] Add isolated tests for automatic IPv4 detection and fallback to the original subscription address.
- [x] Run `bash tests/run.sh` and confirm the new assertions fail before implementation.

### Task 2: Implement IPv4 preference

**Files:**
- Modify: `sui-singbox-migrate.sh`

- [x] Add strict IPv4 validation.
- [x] Add bounded public IPv4 detection using HTTPS endpoints.
- [x] Resolve the direct address during `load_source_config`.
- [x] Apply it only to VLESS, Hysteria2, and TUIC payloads.
- [x] Keep VMess CDN fields unchanged.
- [x] Add `DIRECT_PUBLIC_IP` to usage and show the selected direct address in `--plan`.
- [x] Bump the script version.

### Task 3: Document, verify, and publish

**Files:**
- Modify: `README.md`
- Modify: `GITHUB-UPLOAD-GUIDE.md`
- Modify: `SHA256SUMS`

- [x] Document IPv4 preference, fallback behavior, manual override, and `--force-reimport`.
- [x] Run `bash tests/run.sh`.
- [x] Run `bash -n sui-singbox-migrate.sh`.
- [x] Run `shellcheck sui-singbox-migrate.sh`.
- [x] Regenerate and verify `SHA256SUMS`.

After verification, publish the completed branch to the repository default branch.
