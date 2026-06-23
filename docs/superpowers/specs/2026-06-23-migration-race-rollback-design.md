# Migration Startup Race and Rollback Design

## Problem

On a fresh migration, S-UI reloads its embedded sing-box asynchronously after
the imported TLS, outbound, route, and inbound objects are saved. The current
health check inspects the four listener ports only once. On the reproduced VPS,
that check ran before the reload completed, reported three missing listeners,
and triggered rollback even though S-UI opened all three ports seconds later.

Rollback then stopped only `s-ui`. It did not first stop `argo` and the restored
legacy `sing-box`, so those processes could recreate files under
`/etc/sing-box` while the backup was copied. A delayed S-UI process also
survived after its files and unit were removed. It retained ports 2095, 2096,
and the node ports, while the restored legacy core repeatedly failed with
`address already in use`.

## Design

### Listener readiness

Replace the single listener snapshot with a bounded readiness loop. The loop
checks all four node ports once per second for up to 30 seconds and succeeds
only when every port is listening in the same iteration. If the timeout is
reached, print each still-missing port and fail migration.

The same readiness helper is used before and after the deliberate S-UI restart
in the health check.

### Quiescent rollback

Before restoring any files:

1. Disable and stop S-UI and its Argo synchronization units.
2. Stop legacy `sing-box` and `argo`.
3. Terminate residual S-UI and Argo processes by their installation paths.
4. Wait until the panel, subscription, VMess, and migrated node ports are free.
5. Remove or restore S-UI according to whether it existed in the backup.
6. Restore `/etc/sing-box`, unit files, and the Nginx fragment.
7. Reload systemd, then restore the original service enabled/active states.

This ordering prevents writers from racing with `cp`, prevents orphaned S-UI
listeners, and starts the legacy core only after its ports are available.

### Tests

Add lifecycle tests with mocked `ss`, `systemctl`, sleep, and process cleanup:

- listener readiness retries and eventually succeeds;
- listener readiness reports a timeout when a port never appears;
- rollback stops all competing services before copying backup data;
- rollback terminates residual processes before restarting legacy services.

The existing parser, payload, route, subscription, and version-state tests
must continue to pass.

## Scope

The change does not alter protocol configuration, public address selection,
panel settings, credentials, ports, or user data behavior. It only changes
startup readiness and failure recovery.

## End-to-End Acceptance

On the authorized Ubuntu VPS:

1. Remove both old installations and all migration artifacts.
2. Install the upstream `eooce/sing-box` script from a clean state.
3. Confirm the four original node definitions and listeners exist.
4. Run migration `--plan`.
5. Run the fixed migration using the VPS public IPv4.
6. Confirm S-UI, Argo, sync units, six expected ports, route `direct`, four
   generated subscription schemes, and the absence of rollback or routing
   errors.

