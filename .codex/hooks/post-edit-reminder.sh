#!/bin/bash
# Claude Code Post-Edit Hook
# Reminds about related files when editing specific patterns

EDITED_FILE="$1"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MISTAKE_LOG="$PROJECT_ROOT/.claude/cache/mistake-candidates.jsonl"

# Get filename only
FILENAME=$(basename "$EDITED_FILE")
DIRNAME=$(dirname "$EDITED_FILE")

# Related file reminders based on patterns
case "$EDITED_FILE" in
    *"/packer/scripts/"*)
        echo "[Reminder] Script modified: $FILENAME"
        echo "  -> Check all *.pkr.hcl templates include this script in provisioner"
        echo "  -> Update 07-check-tuning.sh if adding new settings"
        ;;
    *".pkr.hcl")
        echo "[Reminder] Packer template modified: $FILENAME"
        echo "  -> Run './build.sh validate' to verify syntax"
        echo "  -> Ensure other arch templates have similar changes"
        ;;
    *"/http/autoinstall/"*)
        echo "[Reminder] Cloud-init config modified: $FILENAME"
        echo "  -> Changes affect all box builds"
        echo "  -> Test with './build.sh vmware-arm64' first"
        ;;
    *"upload-boxes.sh"|*"upload-all.sh")
        echo "[Reminder] Upload script modified"
        echo "  -> Verify Vagrant Cloud credentials are set"
        echo "  -> Check version number in script"
        ;;
    *".github/workflows/"*)
        echo "[Reminder] CI workflow modified: $FILENAME"
        echo "  -> Check both build-amd64.yml and build-arm64.yml for consistency"
        ;;
esac

# Track edit frequency for mistake detection
if [ -f "$MISTAKE_LOG" ]; then
    EDIT_COUNT=$(grep -c "\"file\":\"$EDITED_FILE\"" "$MISTAKE_LOG" 2>/dev/null || echo "0")
    if [ "$EDIT_COUNT" -ge 2 ]; then
        echo ""
        echo "[Warning] File edited $((EDIT_COUNT + 1)) times in this session: $FILENAME"
        echo "  -> Consider reviewing approach if encountering repeated issues"
    fi
fi

# Log edit event
mkdir -p "$(dirname "$MISTAKE_LOG")"
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"file\":\"$EDITED_FILE\",\"action\":\"edit\"}" >> "$MISTAKE_LOG"
