#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# based on
# https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh

# Fetch GitHub meta information and aggregate their IP ranges
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges" >&2
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields" >&2
    exit 1
fi

echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | sort -u

# skip analytics domains.. not necessary
# "sentry.io" \ 
# "statsig.anthropic.com" \
# "statsig.com" \

# Resolve and output other allowed domains
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain" >&2
        exit 1
    fi
    echo "$ips"
done
