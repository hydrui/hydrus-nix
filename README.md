# Hydrus Nix

## What is this?

This is a bunch of Nix expressions for the Hydrus ecosystem.

This includes:

- Packages, which you can install or run without installing using Nix.

- NixOS modules, which you can use on Nix to declaratively manage a hydrus client, hydownloader, and more.

- NixOS tests, which run integration tests to ensure that the Nix expressions continue to work as expected as everything is updated.

A combination of automated testing and automatic updates is hoped to ensure that the packages can stay up-to-date with minimal breakage. In addition, future expansion of the integration testing suite may prove useful to catch certain kinds of bugs upstream that may otherwise go unnoticed.

## How do I use this?

The documentation is still a work-in-progress, but you can already use this flake to run the latest versions of programs provided by it. For example, you can run the hydrus client like this:

```
nix run github:hydrui/hydrus-nix#hydrus
```

More documentation coming soon.
