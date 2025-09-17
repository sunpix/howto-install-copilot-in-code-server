#!/usr/bin/env bash

# Extract VS Code version from code-server
get_vscode_version() {
    code-server --version 2>/dev/null | grep "with Code" | sed 's/.*with Code //'
}

# Get user-data-dir from running code-server process
get_user_data_dir() {
    # Use ps with POSIX-compliant options
    local process_info
    if command -v ps >/dev/null 2>&1; then
        # Try BSD-style first (macOS), fallback to POSIX
        process_info=$(ps aux 2>/dev/null | grep -v grep | grep "code-server" | head -n 1) ||
        process_info=$(ps -ef 2>/dev/null | grep -v grep | grep "code-server" | head -n 1)
    fi

    if [ -n "$process_info" ]; then
        echo "$process_info" | grep -o -- '--user-data-dir=[^ ]*' | sed 's/--user-data-dir=//'
    fi
}

# Find compatible extension version
find_compatible_version() {
    local extension_id="$1"
    local vscode_version="$2"

    local response
    response=$(curl -s -X POST "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json;api-version=3.0-preview.1" \
        -d "{
            \"filters\": [{
                \"criteria\": [
                    {\"filterType\": 7, \"value\": \"$extension_id\"},
                    {\"filterType\": 12, \"value\": \"4096\"}
                ],
                \"pageSize\": 50
            }],
            \"flags\": 4112
        }")

    echo "$response" | jq -r --arg vscode_version "$vscode_version" '
        .results[0].extensions[0].versions[] |
        select(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]*$")) |
        select(.version | length < 8) |
        {
            version: .version,
            engine: (.properties[] | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value)
        } |
        select(.engine | ltrimstr("^") | split(".") |
            map(split("-")[0] | tonumber?) as $engine_parts |
            ($vscode_version | split(".") | map(tonumber)) as $vscode_parts |
            (
                ($engine_parts[0] // 0) < $vscode_parts[0] or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) < $vscode_parts[1]) or
                (($engine_parts[0] // 0) == $vscode_parts[0] and ($engine_parts[1] // 0) == $vscode_parts[1] and ($engine_parts[2] // 0) <= $vscode_parts[2])
            )
        ) |
        .version' | head -n 1
}

# Install extension
install_extension() {
    local extension_id="$1"
    local version="$2"
    local user_data_dir="$3"
    local extension_name
    extension_name=$(echo "$extension_id" | cut -d'.' -f2)
    local temp_dir="/tmp/code-extensions"

    echo "Installing $extension_id v$version..."

    # Create temp directory
    mkdir -p "$temp_dir"

    # Download
    echo "  Downloading..."
    # Use curl with portable options (--progress-bar not available everywhere)
    curl -L "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/$extension_name/$version/vspackage" \
        -o "$temp_dir/$extension_name.vsix.gz"

    if [ ! -f "$temp_dir/$extension_name.vsix.gz" ]; then
        echo "  ✗ Download failed for $extension_id"
        return 1
    fi

    # Decompress (handle both gunzip and gzip -d)
    if command -v gunzip >/dev/null 2>&1; then
        gunzip -f "$temp_dir/$extension_name.vsix.gz"
    else
        gzip -df "$temp_dir/$extension_name.vsix.gz"
    fi

    # Install with user-data-dir if provided
    if [ -n "$user_data_dir" ]; then
        code-server --user-data-dir="$user_data_dir" --force --install-extension "$temp_dir/$extension_name.vsix"
    else
        code-server --force --install-extension "$temp_dir/$extension_name.vsix"
    fi

    # Clean up
    rm -f "$temp_dir/$extension_name.vsix"

    echo "  ✓ $extension_id installed successfully!"
    return 0
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()

    # Check for required commands
    for cmd in curl jq code-server; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    # Check for either gunzip or gzip
    if ! command -v gunzip >/dev/null 2>&1 && ! command -v gzip >/dev/null 2>&1; then
        missing_deps+=("gunzip/gzip")
    fi

    if [ "${#missing_deps[@]}" -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Main script
echo "GitHub Copilot Extensions Installer"
echo "===================================="
echo ""

# Check dependencies
check_dependencies

# Get VS Code version
VSCODE_VERSION="$(get_vscode_version)"

if [ -z "$VSCODE_VERSION" ]; then
    echo "Error: Could not extract VS Code version from code-server"
    exit 1
fi

echo "Detected VS Code version: $VSCODE_VERSION"

# Check for user-data-dir in running code-server
USER_DATA_DIR="$(get_user_data_dir)"
if [ -n "$USER_DATA_DIR" ]; then
    echo "Detected user-data-dir: $USER_DATA_DIR"
fi
echo ""

# Extensions to install
# Use portable array declaration
EXTENSIONS="GitHub.copilot GitHub.copilot-chat"
FAILED=0

# Iterate through space-separated list for portability
for ext in $EXTENSIONS; do
    echo "Processing $ext..."

    # Find compatible version
    version="$(find_compatible_version "$ext" "$VSCODE_VERSION")"

    if [ -z "$version" ]; then
        echo "  ✗ No compatible version found for $ext"
        FAILED="$((FAILED + 1))"
    else
        echo "  Found compatible version: $version"
        if ! install_extension "$ext" "$version" "$USER_DATA_DIR"; then
            FAILED="$((FAILED + 1))"
        fi
    fi
    echo ""
done

# Summary
echo "===================================="
if [ $FAILED -eq 0 ]; then
    echo "✓ All extensions installed successfully!"
    # Clean up temp directory on success
    rm -rf /tmp/code-extensions
else
    echo "⚠ Completed with $FAILED error(s)"
    exit 1
fi
