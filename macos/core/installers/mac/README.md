# Offline installers (macOS)

Drop `.dmg` or `.pkg` installers here for machines with no network. On macOS the kit
installs through Homebrew when it can, so in practice this folder stays empty.

The nesting (`core/installers/mac/`) is not a typo: the macOS core looks for installers in
exactly `$SCRIPT_DIR/installers/mac`, and the path is kept as-is rather than changed for
tidiness.

Binaries here are gitignored — this file is the only tracked thing in the folder.
