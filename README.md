# nix-readonly

Lightweight, read-only VMs for NixOS using KVM & ZFS.

## How it works

You can define your VMs in Nix, and upgrade them together with your system. The
resulting VM **must** be rebooted for an upgrade.

The VM will have the host `/nix` mounted read-only through the `virtfs` KVM
driver, which is effectively a paravirtualized 9pfs.

A runner script will automatically create ZFS volumes for persisted
directories, and mount them through `virtfs`. This is a good way to control
persistence for *some* paths, but not the entirety of the system.

Note that Docker is currently not usable through `virtfs`, so you can't persist
your `/var/lib/docker`. You may consider this either a feature or a bug,
depending on your use case.

## How to use

Check out the [example](https://github.com/rsdy/nix-readonly/tree/main/example)
directory for a working example using Flakes.

## License

Public domain
