#!/bin/bash
# Claude Code AgentStop Hook
# Verification loop - 작업 완료 시 자동 검증

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 0

echo ""
echo "=== Auto Verification ==="

# 1. Check if packer files were modified
PACKER_CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -c "\.pkr\.hcl$" || echo "0")
SCRIPT_CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -c "packer/scripts/" || echo "0")

if [ "$PACKER_CHANGED" -gt 0 ] || [ "$SCRIPT_CHANGED" -gt 0 ]; then
    echo "[Verify] Packer templates or scripts modified"

    # Run packer validate
    if command -v packer &> /dev/null; then
        echo "[Running] packer validate..."
        cd packer && packer validate . 2>&1 | tail -3
        VALIDATE_RESULT=$?
        cd "$PROJECT_ROOT"

        if [ $VALIDATE_RESULT -eq 0 ]; then
            echo "[OK] Packer validation passed"
        else
            echo "[WARN] Packer validation failed - please check"
        fi
    fi
fi

# 2. Check script permissions
MISSING_EXEC=$(find packer/scripts -name "*.sh" ! -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
if [ "$MISSING_EXEC" -gt 0 ]; then
    echo "[WARN] $MISSING_EXEC script(s) missing execute permission"
    find packer/scripts -name "*.sh" ! -perm -u+x 2>/dev/null
fi

# 3. Summary of changes
TOTAL_CHANGED=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "[Summary] $TOTAL_CHANGED file(s) modified"
git diff --stat HEAD 2>/dev/null | tail -1

echo "==========================="
