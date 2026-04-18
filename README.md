# zvm - Zig Version Manager

A minimal Zig version manager written in Bash.

## Features

- List available Zig versions for download
- Install, uninstall, and switch between Zig versions
- Automatic SHA256 checksum verification
- Download caching
- Supports Linux (x86_64 / aarch64)

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/xinyang-go/zvm/main/install.sh | bash
```

Install to a custom location:

```bash
curl -fsSL https://raw.githubusercontent.com/xinyang-go/zvm/main/install.sh | bash -s -- /path/to/dir
```

Restart your shell after installation.

## Manual Install

```bash
mkdir -p ~/.zvm
curl -fsSL https://raw.githubusercontent.com/xinyang-go/zvm/main/zvm.sh -o ~/.zvm/zvm
chmod +x ~/.zvm/zvm
```

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export PATH="$HOME/.zvm/zig:$HOME/.zvm:$PATH"
```

## Usage

```bash
zvm install 0.16.0       # Install a specific version
zvm install master       # Install latest nightly build
zvm use 0.16.0           # Switch to a version
zvm ls                   # List installed versions
zvm ls-remote            # List available versions for download
zvm uninstall 0.16.0     # Uninstall a version
zvm help                  # Show help
```

## Directory Structure

```
~/.zvm/
├── zvm                  # zvm script
├── zig -> versions/0.16.0/  # active version symlink
├── versions/
│   ├── 0.16.0/          # installed versions
│   └── master/
└── cache/               # download cache
```

## Dependencies

- [curl](https://curl.se/)
- [jq](https://stedolan.github.io/jq/)

## License

MIT
