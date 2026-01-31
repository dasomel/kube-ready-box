#!/usr/bin/env bash
#===============================================================================
# Ralph - Autonomous AI Development Loop
# by Geoffrey Huntley (https://ghuntley.com/ralph/)
#
# Usage:
#   .claude/scripts/ralph.sh [PROMPT_FILE] [OPTIONS]
#
# Options:
#   --max-iterations N   최대 반복 횟수 (기본: 무제한)
#   --delay N            반복 간 대기 시간 초 (기본: 5)
#   --safe               권한 스킵 없이 실행
#   --dry-run            실제 실행 없이 프롬프트만 출력
#===============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMPT_FILE="${1:-${PROJECT_DIR}/PROMPT.md}"
MAX_ITERATIONS=0  # 0 = unlimited
DELAY=5
SAFE_MODE=false
DRY_RUN=false
ITERATION=0

# Parse arguments
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --delay)
      DELAY="$2"
      shift 2
      ;;
    --safe)
      SAFE_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate prompt file
if [[ ! -f "${PROMPT_FILE}" ]]; then
  echo "Error: PROMPT file not found: ${PROMPT_FILE}"
  echo ""
  echo "Create a PROMPT.md file first. Template available at:"
  echo "  .claude/templates/PROMPT.md"
  exit 1
fi

# Log file
LOG_DIR="${PROJECT_DIR}/.claude/cache/ralph-logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/ralph-$(date +%Y%m%d-%H%M%S).log"

echo "==============================================="
echo "  Ralph - Autonomous Development Loop"
echo "==============================================="
echo "Prompt:      ${PROMPT_FILE}"
echo "Max Iter:    ${MAX_ITERATIONS:-unlimited}"
echo "Delay:       ${DELAY}s"
echo "Safe Mode:   ${SAFE_MODE}"
echo "Log:         ${LOG_FILE}"
echo "==============================================="
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Build claude command
CLAUDE_CMD="claude"
if [[ "${SAFE_MODE}" == "false" ]]; then
  CLAUDE_CMD="${CLAUDE_CMD} --dangerously-skip-permissions"
fi

# Main loop
while true; do
  ITERATION=$((ITERATION + 1))

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iteration #${ITERATION}" | tee -a "${LOG_FILE}"

  # Check max iterations
  if [[ ${MAX_ITERATIONS} -gt 0 ]] && [[ ${ITERATION} -gt ${MAX_ITERATIONS} ]]; then
    echo "Max iterations reached. Stopping."
    break
  fi

  # Dry run mode
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "--- PROMPT ---"
    cat "${PROMPT_FILE}"
    echo "--- END PROMPT ---"
    echo "(dry-run mode, not executing)"
    break
  fi

  # Execute Claude
  echo "Running Claude..." | tee -a "${LOG_FILE}"
  if cat "${PROMPT_FILE}" | ${CLAUDE_CMD} 2>&1 | tee -a "${LOG_FILE}"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iteration #${ITERATION} completed" | tee -a "${LOG_FILE}"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iteration #${ITERATION} failed" | tee -a "${LOG_FILE}"
  fi

  # Git status snapshot
  echo "--- Git Status ---" >> "${LOG_FILE}"
  git -C "${PROJECT_DIR}" status --short >> "${LOG_FILE}" 2>/dev/null || true
  echo "--- End Git Status ---" >> "${LOG_FILE}"

  # Delay before next iteration
  echo "Waiting ${DELAY}s before next iteration..." | tee -a "${LOG_FILE}"
  sleep "${DELAY}"
done

echo ""
echo "Ralph finished. Log: ${LOG_FILE}"
