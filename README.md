# GitHub Copilot Code Server Installer

Installs GitHub Copilot and Copilot Chat extensions in code-server by automatically finding and downloading compatible versions based on your code-server VS Code version.

## Usage

```bash
chmod +x install-copilot.sh && ./install-copilot.sh
```

Or run directly:

```bash
curl -fsSL https://raw.githubusercontent.com/sunpix/howto-install-copilot-in-code-server/refs/heads/main/install-copilot.sh | bash
```

## Requirements

- code-server
- curl
- jq
- gzip or gunzip
