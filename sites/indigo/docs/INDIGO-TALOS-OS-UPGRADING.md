# Upgrading Talos Linux OS

Covering upgrading Talos Linux OS, which includes a new installer image.

Updating the underlying Talos Linux OS will *not* update Kubernetes, that's handled via [INDIGO-TALOS-K8S-UPGRADING.md](./INDIGO-TALOS-K8S-UPGRADING.md).

Always upgrade to the latest patch release of the current minor release before attempting a minor release upgrade.

Always ensure your local `talosctl` is running the latest available version before attempting any upgrades.

## Build the new config(s) and upgrade commands
TBD

## Perform the upgrades to Worker Node(s)
TBD

## Perform the upgrades to Control Plane Node(s)
TBD

## Validate Upgrade
For each Node IP run the following command to verify the Server version is the correct one, if not the upgrade may have failed and the node rolled itself back to the previous version.

```bash
talosctl --talosconfig templates/dal-indigo-core-1/talosconfig -n 192.168.77.199 --version
```
