#!/bin/bash
# Claude Code Session Start Hook
# Automatically loads project context

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTEXT_FILE="$PROJECT_ROOT/.claude/cache/project-context.md"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"

echo "=== Kube Ready Box Project Context ==="
echo ""

# Show quick overview from CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
    echo "[Project] Kubernetes-ready Ubuntu 24.04 Vagrant Box"
    echo "[Tech] Packer + VirtualBox/VMware + Bash"
    echo ""
fi

# Show current branch and status
echo "[Git Branch] $(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo 'N/A')"
echo "[Git Status] $(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ') changed files"
echo ""

# Show build status
if [ -d "$PROJECT_ROOT/packer" ]; then
    BOX_COUNT=$(find "$PROJECT_ROOT/packer" -name "*.box" 2>/dev/null | wc -l | tr -d ' ')
    echo "[Built Boxes] $BOX_COUNT box file(s) found"
fi

echo ""
echo "Key commands: ./packer/build.sh [init|validate|vmware-arm64|all]"
echo "Docs: CLAUDE.md, .agent/AGENT.md"
echo "==================================="
