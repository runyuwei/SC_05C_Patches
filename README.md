# Gerrit Patch Management Tools

A collection of bash scripts for managing Gerrit patches across multiple repositories.

## Quick Start

1. Edit `patch_config_flexible.conf` - Set your Gerrit username and patch list
(Optional: 2. Run `./apply_patches_flexible.sh --dry-run` - Preview operations)
3. Run `./apply_patches_flexible.sh` - Apply patches
4. Run `./clean_patches.sh --force` - Reset repositories when needed

## Files

- **`apply_patches_flexible.sh`** - Main patch application script
- **`clean_patches.sh`** - Repository cleanup and reset script  
- **`patch_config_flexible.conf`** - Configuration file for patches and repositories
- **`PATCHES_README.md`** - Detailed usage guide (Chinese)

## Features

- Flexible configuration system
- Multiple repository support
- Dry-run mode for safety
- Comprehensive logging
- Proxy support for corporate environments
- Branch management and cleanup

## Environment

Designed for Intel internal Gerrit server with corporate proxy support.

## Usage

See [PATCHES_README.md](PATCHES_README.md) for detailed Chinese documentation.
