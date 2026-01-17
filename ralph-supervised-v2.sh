#!/bin/bash
# Ralph Supervised v2 - Clean rewrite
# Usage: ./ralph-supervised-v2.sh [max_iterations] [--resume]
#
# Design principles:
# 1. PAUSE by default - only continue on explicit CONTINUE signal
# 2. Fail fast - validate everything upfront
# 3. Proper exit codes - no pipe tricks that swallow errors
# 4. Timeouts - never hang indefinitely
# 5. Single source of truth - one way to run Claude, one way to check results
# 6. Full logging - every Claude interaction is preserved
# 7. Resumable - can continue from last successful iteration

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Parse arguments
MAX_ITERATIONS=10
RESUME_MODE=false
START_ITERATION=1

for arg in "$@"; do
  case $arg in
    --resume)
      RESUME_MODE=true
      ;;
    [0-9]*)
      MAX_ITERATIONS=$arg
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Files
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
GUIDANCE_FILE="$SCRIPT_DIR/guidance.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
CONFIG_FILE="$SCRIPT_DIR/ralph-config.json"
STATE_FILE="$SCRIPT_DIR/.ralph-state.json"
LOCKFILE="$SCRIPT_DIR/.ralph.lock"

# Session logging directory (persisted, not temp)
SESSION_ID=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$SCRIPT_DIR/logs/$SESSION_ID"

# Temp directory for working files
TEMP_DIR=$(mktemp -d)

# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP HANDLER
# Preserves logs, cleans temp, releases lock
# ═══════════════════════════════════════════════════════════════════════════════
cleanup() {
  local exit_code=$?

  # Release lock
  if [ -n "${LOCK_FD:-}" ]; then
    if [ "$LOCK_FD" = "mkdir" ]; then
      # macOS mkdir-based lock
      rm -rf "${LOCKFILE}.d"
    else
      # Linux flock-based lock
      flock -u $LOCK_FD 2>/dev/null || true
    fi
  fi

  # Clean temp but preserve logs
  rm -rf "$TEMP_DIR"

  # Log session end
  if [ -d "$LOG_DIR" ]; then
    echo "Session ended: $(date)" >> "$LOG_DIR/session.log"
    echo "Exit code: $exit_code" >> "$LOG_DIR/session.log"
  fi

  exit $exit_code
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# LOAD CONFIGURATION
# Models can be overridden via ralph-config.json
# ═══════════════════════════════════════════════════════════════════════════════

# Defaults
GRANDMA_MODEL="claude-opus-4-5-20251101"
MODEL_LOW="claude-3-5-haiku-20241022"
MODEL_MEDIUM="claude-sonnet-4-20250514"
MODEL_HIGH="claude-opus-4-5-20251101"
CLAUDE_TIMEOUT=300
MAX_RETRIES=3
RETRY_DELAY=5

# Override from config file if exists
if [ -f "$CONFIG_FILE" ]; then
  GRANDMA_MODEL=$(jq -r '.models.grandma // "claude-opus-4-5-20251101"' "$CONFIG_FILE")
  MODEL_LOW=$(jq -r '.models.low // "claude-3-5-haiku-20241022"' "$CONFIG_FILE")
  MODEL_MEDIUM=$(jq -r '.models.medium // "claude-sonnet-4-20250514"' "$CONFIG_FILE")
  MODEL_HIGH=$(jq -r '.models.high // "claude-opus-4-5-20251101"' "$CONFIG_FILE")
  CLAUDE_TIMEOUT=$(jq -r '.timeout // 300' "$CONFIG_FILE")
  MAX_RETRIES=$(jq -r '.max_retries // 3' "$CONFIG_FILE")
  RETRY_DELAY=$(jq -r '.retry_delay // 5' "$CONFIG_FILE")
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════════
# TIMEOUT FALLBACK FOR MACOS
# Uses background process + kill approach when coreutils not installed
# ═══════════════════════════════════════════════════════════════════════════════
timeout_fallback() {
  local duration=$1
  shift

  # Run command in background
  "$@" &
  local pid=$!

  # Wait for completion or timeout
  local count=0
  while kill -0 $pid 2>/dev/null; do
    if [ $count -ge $duration ]; then
      kill -9 $pid 2>/dev/null
      wait $pid 2>/dev/null
      return 124  # Same as GNU timeout
    fi
    sleep 1
    count=$((count + 1))
  done

  # Get exit code
  wait $pid
  return $?
}

# ═══════════════════════════════════════════════════════════════════════════════
# CORE FUNCTION: Run Claude with proper error handling
#
# This is the ONLY way to call Claude. No other method should be used.
# Returns: 0 on success, 1 on failure
# Output: Written to file path passed as $4
# Logs: Saved to $LOG_DIR for debugging
# ═══════════════════════════════════════════════════════════════════════════════
run_claude() {
  local model="$1"
  local prompt="$2"
  local description="$3"
  local output_file="$4"

  local attempt=1
  local exit_code=1

  # Save prompt to log (sanitized description for filename)
  local log_name=$(echo "$description" | tr ' ' '-' | tr -cd '[:alnum:]-')
  local prompt_log="$LOG_DIR/${log_name}-prompt.md"
  echo "$prompt" > "$prompt_log"

  while [ $attempt -le $MAX_RETRIES ]; do
    echo -e "${BLUE}  [$description] Attempt $attempt of $MAX_RETRIES${NC}"

    # Clear output file
    > "$output_file"

    # Write prompt to temp file to avoid argument length limits
    local prompt_file="$TEMP_DIR/prompt-$$.txt"
    echo "$prompt" > "$prompt_file"

    # Run Claude with timeout, using stdin for prompt (avoids arg length limits)
    # The timeout command returns 124 if it times out
    set +e
    $TIMEOUT_CMD $CLAUDE_TIMEOUT claude \
      --model "$model" \
      --dangerously-skip-permissions \
      --print \
      < "$prompt_file" \
      > "$output_file" 2>&1
    exit_code=$?
    set -e

    # Clean up prompt file
    rm -f "$prompt_file"

    # Check timeout
    if [ $exit_code -eq 124 ]; then
      echo -e "${YELLOW}  [$description] Timed out after ${CLAUDE_TIMEOUT}s${NC}"
      log_attempt "$log_name" "$attempt" "TIMEOUT" "$output_file"
      attempt=$((attempt + 1))
      sleep $((RETRY_DELAY * attempt))  # Exponential backoff
      continue
    fi

    # Check Claude exit code
    if [ $exit_code -ne 0 ]; then
      echo -e "${YELLOW}  [$description] Claude exited with code $exit_code${NC}"
      log_attempt "$log_name" "$attempt" "EXIT_$exit_code" "$output_file"
      attempt=$((attempt + 1))
      sleep $((RETRY_DELAY * attempt))
      continue
    fi

    # Check for API errors in output (more specific patterns to avoid false positives)
    if grep -qE "^(Error:|error originated|APIError|RateLimitError)" "$output_file" || \
       grep -qE "(ETIMEDOUT|ECONNRESET|ECONNREFUSED|socket hang up|overloaded_error)" "$output_file"; then
      echo -e "${YELLOW}  [$description] API error detected in output${NC}"
      log_attempt "$log_name" "$attempt" "API_ERROR" "$output_file"
      attempt=$((attempt + 1))
      sleep $((RETRY_DELAY * attempt))
      continue
    fi

    # Check output has substance (more than 50 chars)
    local output_size=$(wc -c < "$output_file")
    if [ "$output_size" -lt 50 ]; then
      echo -e "${YELLOW}  [$description] Output too short (${output_size} bytes)${NC}"
      log_attempt "$log_name" "$attempt" "TOO_SHORT" "$output_file"
      attempt=$((attempt + 1))
      sleep $((RETRY_DELAY * attempt))
      continue
    fi

    # Success - save to log
    log_attempt "$log_name" "$attempt" "SUCCESS" "$output_file"
    echo -e "${GREEN}  [$description] Success${NC}"
    return 0
  done

  # All retries exhausted
  echo -e "${RED}  [$description] FAILED after $MAX_RETRIES attempts${NC}"
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Log an attempt for debugging
# ═══════════════════════════════════════════════════════════════════════════════
log_attempt() {
  local name="$1"
  local attempt="$2"
  local status="$3"
  local output_file="$4"

  local log_file="$LOG_DIR/${name}-attempt${attempt}-${status}.txt"
  cp "$output_file" "$log_file" 2>/dev/null || true
  echo "$(date): $name attempt $attempt: $status" >> "$LOG_DIR/session.log"
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Check for Grandma signal
#
# Uses flexible regex to handle whitespace variations:
#   <grandma>CONTINUE</grandma>
#   <grandma> CONTINUE </grandma>
#   <grandma>\nCONTINUE\n</grandma>
#
# Returns:
#   0 if CONTINUE found
#   1 if PAUSE found or no clear signal (PAUSE by default)
# ═══════════════════════════════════════════════════════════════════════════════
check_grandma_signal() {
  local output_file="$1"

  # Flexible regex: allow whitespace/newlines around the signal word
  # Use perl for multi-line matching (more reliable than grep -Pz)
  if perl -0777 -ne 'exit 0 if /<grandma>\s*CONTINUE\s*<\/grandma>/s; exit 1' "$output_file" 2>/dev/null; then
    return 0
  fi

  if perl -0777 -ne 'exit 0 if /<grandma>\s*PAUSE\s*<\/grandma>/s; exit 1' "$output_file" 2>/dev/null; then
    echo -e "${RED}  Grandma says: PAUSE${NC}"
    return 1
  fi

  # No clear signal = PAUSE (this is the key fix)
  echo -e "${RED}  Grandma gave no clear signal - treating as PAUSE${NC}"
  echo -e "${RED}  (Expected <grandma>CONTINUE</grandma> or <grandma>PAUSE</grandma>)${NC}"
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Check for session signal (same flexible pattern)
# ═══════════════════════════════════════════════════════════════════════════════
check_session_signal() {
  local output_file="$1"
  local expected_signal="$2"  # READY or BLOCKED

  if perl -0777 -ne "exit 0 if /<session>\\s*${expected_signal}\\s*<\\/session>/s; exit 1" "$output_file" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Validate PRD schema
# Ensures PRD has expected structure before proceeding
# ═══════════════════════════════════════════════════════════════════════════════
validate_prd_schema() {
  local prd_file="$1"

  # Check file exists and is valid JSON
  if ! jq empty "$prd_file" 2>/dev/null; then
    echo "ERROR: PRD is not valid JSON"
    return 1
  fi

  # Check required fields exist
  local has_stories=$(jq 'has("userStories")' "$prd_file")
  if [ "$has_stories" != "true" ]; then
    echo "ERROR: PRD missing 'userStories' array"
    return 1
  fi

  # Check userStories is an array with items
  local story_count=$(jq '.userStories | length' "$prd_file")
  if [ "$story_count" -eq 0 ]; then
    echo "ERROR: PRD has empty 'userStories' array"
    return 1
  fi

  # Check each story has required fields
  local invalid_stories=$(jq '[.userStories[] | select(
    (has("id") | not) or
    (has("title") | not) or
    (has("passes") | not)
  )] | length' "$prd_file")

  if [ "$invalid_stories" -gt 0 ]; then
    echo "ERROR: $invalid_stories stories missing required fields (id, title, passes)"
    return 1
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Save state for resume capability
# ═══════════════════════════════════════════════════════════════════════════════
save_state() {
  local iteration="$1"
  local phase="$2"
  local status="$3"

  cat > "$STATE_FILE" <<EOF
{
  "last_iteration": $iteration,
  "last_phase": "$phase",
  "status": "$status",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "session_id": "$SESSION_ID",
  "log_dir": "$LOG_DIR"
}
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Load state for resume
# ═══════════════════════════════════════════════════════════════════════════════
load_state() {
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  local status=$(jq -r '.status' "$STATE_FILE")
  if [ "$status" != "paused" ] && [ "$status" != "in_progress" ]; then
    return 1
  fi

  START_ITERATION=$(jq -r '.last_iteration' "$STATE_FILE")
  local last_phase=$(jq -r '.last_phase' "$STATE_FILE")

  # If we completed an iteration, start from the next one
  if [ "$last_phase" = "grandma_review" ]; then
    START_ITERATION=$((START_ITERATION + 1))
  fi

  echo "$START_ITERATION"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Acquire lock to prevent concurrent runs
# Uses flock on Linux, shlock/mkdir fallback on macOS
# ═══════════════════════════════════════════════════════════════════════════════
acquire_lock() {
  # Check if flock is available (Linux)
  if command -v flock &> /dev/null; then
    exec 200>"$LOCKFILE"
    LOCK_FD=200
    if ! flock -n 200; then
      echo -e "${RED}ERROR: Another Ralph instance is already running${NC}"
      echo -e "${RED}Lock file: $LOCKFILE${NC}"
      echo -e "${RED}If this is incorrect, remove the lock file and try again${NC}"
      exit 1
    fi
    echo $$ > "$LOCKFILE"
  else
    # macOS fallback: use mkdir (atomic operation)
    local lock_dir="${LOCKFILE}.d"

    if mkdir "$lock_dir" 2>/dev/null; then
      # Successfully acquired lock
      echo $$ > "$lock_dir/pid"

      # Set up cleanup to remove lock dir on exit
      LOCK_FD="mkdir"  # Flag for cleanup function
    else
      # Check if the lock is stale (process no longer running)
      if [ -f "$lock_dir/pid" ]; then
        local old_pid=$(cat "$lock_dir/pid" 2>/dev/null)
        if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
          # Stale lock, remove and retry
          rm -rf "$lock_dir"
          if mkdir "$lock_dir" 2>/dev/null; then
            echo $$ > "$lock_dir/pid"
            LOCK_FD="mkdir"
            return 0
          fi
        fi
      fi

      echo -e "${RED}ERROR: Another Ralph instance is already running${NC}"
      echo -e "${RED}Lock: $lock_dir${NC}"
      echo -e "${RED}If this is incorrect, run: rm -rf $lock_dir${NC}"
      exit 1
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Get model for current story complexity
# ═══════════════════════════════════════════════════════════════════════════════
get_ralph_model() {
  # Validate prd.json exists (already checked at startup, but be safe)
  if [ ! -f "$PRD_FILE" ]; then
    echo "$MODEL_MEDIUM"
    return
  fi

  local complexity
  complexity=$(jq -r '
    .userStories
    | sort_by(.priority)
    | map(select(.passes == false))
    | .[0].complexity // "medium"
  ' "$PRD_FILE" 2>/dev/null) || complexity="medium"

  case "$complexity" in
    "low")  echo "$MODEL_LOW" ;;
    "high") echo "$MODEL_HIGH" ;;
    *)      echo "$MODEL_MEDIUM" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Get current story info
# ═══════════════════════════════════════════════════════════════════════════════
get_current_story() {
  if [ ! -f "$PRD_FILE" ]; then
    echo "No PRD file"
    return
  fi

  jq -r '
    .userStories
    | sort_by(.priority)
    | map(select(.passes == false))
    | .[0]
    | "\(.id // "?") - \(.title // "Unknown") [\(.complexity // "medium")]"
  ' "$PRD_FILE" 2>/dev/null || echo "Could not read story"
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER: Pause with message
# ═══════════════════════════════════════════════════════════════════════════════
pause_loop() {
  local reason="$1"
  local iteration="$2"
  local phase="${3:-unknown}"

  echo ""
  echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}  PAUSED: $reason${NC}"
  echo -e "${RED}  Iteration: $iteration${NC}"
  echo -e "${RED}  Phase: $phase${NC}"
  echo -e "${RED}  Check guidance.txt for details${NC}"
  echo -e "${RED}  Logs: $LOG_DIR${NC}"
  echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  To resume: ./ralph-supervised-v2.sh --resume${NC}"

  echo "$(date): PAUSED at iteration $iteration ($phase) - $reason" >> "$GUIDANCE_FILE"

  # Save state for resume
  save_state "$iteration" "$phase" "paused"

  exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# STARTUP VALIDATION
# Fail fast if environment is not ready
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║  Ralph Supervised v2                                      ║${NC}"
echo -e "${PURPLE}║  Max iterations: $MAX_ITERATIONS                                       ║${NC}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# ACQUIRE LOCK (prevent concurrent runs)
# ═══════════════════════════════════════════════════════════════════════════════
acquire_lock

# ═══════════════════════════════════════════════════════════════════════════════
# CREATE LOG DIRECTORY
# ═══════════════════════════════════════════════════════════════════════════════
mkdir -p "$LOG_DIR"
echo "Session started: $(date)" > "$LOG_DIR/session.log"
echo "Arguments: $*" >> "$LOG_DIR/session.log"
echo -e "${BLUE}Logging to: $LOG_DIR${NC}"

# Use Max subscription
if [[ "${RALPH_USE_SUBSCRIPTION:-true}" == "true" ]]; then
  unset ANTHROPIC_API_KEY
  echo -e "${BLUE}Using Max subscription${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# HANDLE RESUME MODE
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$RESUME_MODE" = true ]; then
  if RESUME_ITERATION=$(load_state); then
    START_ITERATION=$RESUME_ITERATION
    echo -e "${YELLOW}Resuming from iteration $START_ITERATION${NC}"
    echo "Resuming from iteration $START_ITERATION" >> "$LOG_DIR/session.log"
  else
    echo -e "${YELLOW}No valid state to resume from. Starting fresh.${NC}"
  fi
fi

# Validate required files exist
echo -e "${BLUE}Validating environment...${NC}"

if [ ! -f "$PRD_FILE" ]; then
  echo -e "${RED}ERROR: prd.json not found at $PRD_FILE${NC}"
  echo -e "${RED}Cannot proceed without a PRD.${NC}"
  exit 1
fi

# Validate PRD schema (not just existence)
echo -n "  Validating PRD schema... "
if ! validate_prd_schema "$PRD_FILE"; then
  echo -e "${RED}FAILED${NC}"
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# Validate PRD has incomplete stories
INCOMPLETE_COUNT=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null) || INCOMPLETE_COUNT=0
if [ "$INCOMPLETE_COUNT" -eq 0 ]; then
  echo -e "${GREEN}All stories already complete! Nothing to do.${NC}"
  save_state 0 "complete" "complete"
  exit 0
fi
echo -e "${GREEN}  PRD valid: $INCOMPLETE_COUNT incomplete stories${NC}"

# Archive previous run if branch changed
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null) || CURRENT_BRANCH=""

if [ -n "$CURRENT_BRANCH" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null) || LAST_BRANCH=""

  if [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo -e "${YELLOW}  Archiving previous run: $LAST_BRANCH${NC}"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$GUIDANCE_FILE" ] && cp "$GUIDANCE_FILE" "$ARCHIVE_FOLDER/"
    echo -e "${GREEN}  Archived to: $ARCHIVE_FOLDER${NC}"

    # Reset files for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"

    echo "# Grandma's Guidance" > "$GUIDANCE_FILE"
    echo "Started: $(date)" >> "$GUIDANCE_FILE"
    echo "---" >> "$GUIDANCE_FILE"
    echo "" >> "$GUIDANCE_FILE"
    echo "No guidance yet. First iteration starting fresh." >> "$GUIDANCE_FILE"
  fi
fi

# Track current branch for next run
if [ -n "$CURRENT_BRANCH" ]; then
  echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

# Validate prompt files exist
for prompt_file in "prompt-supervised.md" "grandma-preflight.md" "grandma-review.md"; do
  if [ ! -f "$SCRIPT_DIR/$prompt_file" ]; then
    echo -e "${RED}ERROR: Required prompt file missing: $prompt_file${NC}"
    exit 1
  fi
done
echo -e "${GREEN}  Prompt files: OK${NC}"

# Validate Claude CLI is available
if ! command -v claude &> /dev/null; then
  echo -e "${RED}ERROR: claude CLI not found in PATH${NC}"
  exit 1
fi
echo -e "${GREEN}  Claude CLI: OK${NC}"

# Set up timeout command (macOS compatibility)
if command -v timeout &> /dev/null; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout &> /dev/null; then
  TIMEOUT_CMD="gtimeout"
else
  # Fallback: create a timeout function using background process
  # This works on macOS without coreutils
  echo -e "${YELLOW}  Timeout: Using fallback (consider: brew install coreutils)${NC}"
  TIMEOUT_CMD="timeout_fallback"
fi
echo -e "${GREEN}  Timeout: OK ($TIMEOUT_CMD)${NC}"

# Initialize files if needed
[ ! -f "$PROGRESS_FILE" ] && echo "# Ralph Progress Log\nStarted: $(date)\n---" > "$PROGRESS_FILE"
[ ! -f "$GUIDANCE_FILE" ] && echo "# Grandma's Guidance\nStarted: $(date)\n---\n" > "$GUIDANCE_FILE"

echo -e "${GREEN}Environment validated.${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 0: SESSION INITIALIZATION
# Runs ONCE at session start to set up environment
# Uses Haiku for cost efficiency (straightforward setup work)
# ═══════════════════════════════════════════════════════════════════════════════

SESSION_INIT_PROMPT="$SCRIPT_DIR/session-init.md"
SESSION_STATE_FILE="$SCRIPT_DIR/session-state.txt"
INIT_MODEL="$MODEL_LOW"  # Haiku for cost efficiency

echo -e "${PURPLE}───────────────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}  Phase 0: Session Initialization${NC}"
echo -e "${PURPLE}  Model: Haiku (cost-efficient setup)${NC}"
echo -e "${PURPLE}───────────────────────────────────────────────────────────${NC}"

if [ -f "$SESSION_INIT_PROMPT" ]; then
  # Skip session init if resuming (already initialized)
  if [ "$RESUME_MODE" = true ] && [ "$START_ITERATION" -gt 1 ]; then
    echo -e "${YELLOW}Skipping session init (resuming from iteration $START_ITERATION)${NC}"
  else
    INIT_OUTPUT="$TEMP_DIR/init.txt"
    INIT_PROMPT=$(cat "$SESSION_INIT_PROMPT")

    if ! run_claude "$INIT_MODEL" "$INIT_PROMPT" "Session init" "$INIT_OUTPUT"; then
      pause_loop "Session initialization failed after $MAX_RETRIES attempts" "0" "session_init"
    fi

    # Check for BLOCKED signal (flexible whitespace matching)
    if check_session_signal "$INIT_OUTPUT" "BLOCKED"; then
      echo ""
      echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}  Session Initialization: BLOCKED${NC}"
      echo -e "${RED}  Environment issues detected.${NC}"
      echo -e "${RED}  Check session-state.txt for details.${NC}"
      echo -e "${RED}  Logs: $LOG_DIR${NC}"
      echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
      save_state 0 "session_init" "blocked"
      exit 1
    fi

    # Check for READY signal (require explicit signal)
    if check_session_signal "$INIT_OUTPUT" "READY"; then
      echo -e "${GREEN}Session initialized. Environment ready.${NC}"
    else
      echo -e "${RED}Session init gave no clear READY/BLOCKED signal - treating as BLOCKED${NC}"
      echo -e "${RED}(Expected <session>READY</session> or <session>BLOCKED</session>)${NC}"
      echo -e "${RED}Logs: $LOG_DIR${NC}"
      save_state 0 "session_init" "blocked"
      exit 1
    fi
  fi
else
  echo -e "${YELLOW}No session-init.md found. Skipping Phase 0.${NC}"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════════

for i in $(seq $START_ITERATION $MAX_ITERATIONS); do
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Iteration $i of $MAX_ITERATIONS${NC}"
  echo -e "${BLUE}  Story: $(get_current_story)${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

  # Save state: starting iteration
  save_state "$i" "starting" "in_progress"

  # ─────────────────────────────────────────────────────────────────────────────
  # PHASE 1: Grandma Pre-flight
  # ─────────────────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${YELLOW}Phase 1: Grandma Pre-flight (Opus)${NC}"

  PREFLIGHT_OUTPUT="$TEMP_DIR/preflight-$i.txt"
  PREFLIGHT_PROMPT=$(cat "$SCRIPT_DIR/grandma-preflight.md")

  save_state "$i" "grandma_preflight" "in_progress"

  if ! run_claude "$GRANDMA_MODEL" "$PREFLIGHT_PROMPT" "Grandma preflight $i" "$PREFLIGHT_OUTPUT"; then
    pause_loop "Grandma pre-flight failed after $MAX_RETRIES attempts" "$i" "grandma_preflight"
  fi

  if ! check_grandma_signal "$PREFLIGHT_OUTPUT"; then
    pause_loop "Grandma pre-flight did not approve" "$i" "grandma_preflight"
  fi

  echo -e "${GREEN}Pre-flight approved.${NC}"

  # ─────────────────────────────────────────────────────────────────────────────
  # PHASE 2: Ralph Implementation
  # ─────────────────────────────────────────────────────────────────────────────
  echo ""
  RALPH_MODEL=$(get_ralph_model)
  echo -e "${GREEN}Phase 2: Ralph Implementation ($RALPH_MODEL)${NC}"

  RALPH_OUTPUT="$TEMP_DIR/ralph-$i.txt"
  RALPH_PROMPT=$(cat "$SCRIPT_DIR/prompt-supervised.md")

  save_state "$i" "ralph_implementation" "in_progress"

  if ! run_claude "$RALPH_MODEL" "$RALPH_PROMPT" "Ralph implementation $i" "$RALPH_OUTPUT"; then
    pause_loop "Ralph failed after $MAX_RETRIES attempts" "$i" "ralph_implementation"
  fi

  # Check if Ralph completed all tasks (flexible whitespace matching)
  if perl -0777 -ne 'exit 0 if /<promise>\s*COMPLETE\s*<\/promise>/s; exit 1' "$RALPH_OUTPUT" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Ralph completed all tasks!${NC}"
    echo -e "${GREEN}  Finished at iteration $i of $MAX_ITERATIONS${NC}"
    echo -e "${GREEN}  Logs: $LOG_DIR${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    save_state "$i" "complete" "complete"
    exit 0
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # PHASE 3: Grandma Post-Review
  # ─────────────────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${YELLOW}Phase 3: Grandma Post-Review (Opus)${NC}"

  REVIEW_OUTPUT="$TEMP_DIR/review-$i.txt"
  REVIEW_PROMPT=$(cat "$SCRIPT_DIR/grandma-review.md")

  save_state "$i" "grandma_review" "in_progress"

  if ! run_claude "$GRANDMA_MODEL" "$REVIEW_PROMPT" "Grandma review $i" "$REVIEW_OUTPUT"; then
    pause_loop "Grandma review failed after $MAX_RETRIES attempts" "$i" "grandma_review"
  fi

  # Require explicit CONTINUE, otherwise PAUSE
  if ! check_grandma_signal "$REVIEW_OUTPUT"; then
    pause_loop "Grandma review did not approve continuation" "$i" "grandma_review"
  fi

  # Mark iteration complete
  save_state "$i" "grandma_review" "iteration_complete"

  echo -e "${GREEN}Grandma approved. Continuing to next iteration.${NC}"
  echo ""
  sleep 2
done

# ═══════════════════════════════════════════════════════════════════════════════
# MAX ITERATIONS REACHED
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Reached max iterations ($MAX_ITERATIONS)${NC}"
echo -e "${YELLOW}  Not all tasks completed. Check progress.txt${NC}"
echo -e "${YELLOW}  Logs: $LOG_DIR${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"

save_state "$MAX_ITERATIONS" "max_iterations" "max_iterations_reached"
exit 1
