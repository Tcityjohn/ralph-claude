#!/bin/bash
# Ralph Supervised - AI agent loop with Grandma watching
# Usage: ./ralph-supervised.sh [max_iterations]
#
# Ralph does the work. Grandma reviews each iteration and can:
# - Leave guidance for the next iteration
# - PAUSE the loop if something needs human attention
# - Course-correct before mistakes compound

set -e

# Authentication: Claude CLI can use either API credits or Max subscription
# - If you have a Max plan: set RALPH_USE_SUBSCRIPTION=true to use it instead of API credits
# - If you only have API credits: leave ANTHROPIC_API_KEY set (default behavior)
if [[ "${RALPH_USE_SUBSCRIPTION:-true}" == "true" ]]; then
  unset ANTHROPIC_API_KEY
  echo "Using Max subscription (RALPH_USE_SUBSCRIPTION=true)"
fi

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
GUIDANCE_FILE="$SCRIPT_DIR/guidance.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Model configurations
GRANDMA_MODEL="claude-opus-4-5-20251101"
MODEL_LOW="claude-3-5-haiku-20241022"
MODEL_MEDIUM="claude-sonnet-4-20250514"
MODEL_HIGH="claude-opus-4-5-20251101"
INIT_MODEL="$MODEL_LOW"  # Session init uses Haiku for cost efficiency

# Session state file
SESSION_STATE_FILE="$SCRIPT_DIR/session-state.txt"
SESSION_INIT_PROMPT="$SCRIPT_DIR/session-init.md"

# Function to get Ralph's model based on story complexity
get_ralph_model() {
  local prd_file="$1"

  # Find the first incomplete story (ordered by priority) and get its complexity
  local complexity=$(jq -r '
    .userStories
    | sort_by(.priority)
    | map(select(.passes == false))
    | .[0].complexity // "medium"
  ' "$prd_file" 2>/dev/null)

  case "$complexity" in
    "low")
      echo "$MODEL_LOW"
      ;;
    "high")
      echo "$MODEL_HIGH"
      ;;
    *)
      echo "$MODEL_MEDIUM"
      ;;
  esac
}

# Function to get current story info for display
get_current_story_info() {
  local prd_file="$1"
  jq -r '
    .userStories
    | sort_by(.priority)
    | map(select(.passes == false))
    | .[0]
    | "\(.id) - \(.title) [complexity: \(.complexity // "medium")]"
  ' "$prd_file" 2>/dev/null || echo "No incomplete stories"
}

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo -e "${YELLOW}Archiving previous run: $LAST_BRANCH${NC}"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$GUIDANCE_FILE" ] && cp "$GUIDANCE_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

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

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Initialize guidance file if it doesn't exist
if [ ! -f "$GUIDANCE_FILE" ]; then
  echo "# Grandma's Guidance" > "$GUIDANCE_FILE"
  echo "Started: $(date)" >> "$GUIDANCE_FILE"
  echo "---" >> "$GUIDANCE_FILE"
  echo "" >> "$GUIDANCE_FILE"
  echo "No guidance yet. First iteration starting fresh." >> "$GUIDANCE_FILE"
fi

echo ""
echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║  Ralph Supervised - Grandma's Watching                    ║${NC}"
echo -e "${PURPLE}║  Max iterations: $MAX_ITERATIONS                                       ║${NC}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════
# PHASE 0: SESSION INITIALIZATION (Anthropic-style)
# Runs ONCE at session start, not every iteration
# ═══════════════════════════════════════════════════════════
echo -e "${PURPLE}───────────────────────────────────────────────────────────${NC}"
echo -e "${PURPLE}  Phase 0: Session Initialization${NC}"
echo -e "${PURPLE}  Model: Haiku (cost-efficient setup)${NC}"
echo -e "${PURPLE}───────────────────────────────────────────────────────────${NC}"

if [ -f "$SESSION_INIT_PROMPT" ]; then
  INIT_PROMPT=$(cat "$SESSION_INIT_PROMPT")
  INIT_OUTPUT=$(claude --model "$INIT_MODEL" --dangerously-skip-permissions --print "$INIT_PROMPT" 2>&1 | tee /dev/stderr) || true

  # Check if session is blocked
  if echo "$INIT_OUTPUT" | grep -q "<session>BLOCKED</session>"; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Session Initialization: BLOCKED${NC}"
    echo -e "${RED}  Environment issues detected.${NC}"
    echo -e "${RED}  Check session-state.txt for details.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    exit 1
  fi

  echo -e "${GREEN}Session initialized. Environment ready.${NC}"
else
  echo -e "${YELLOW}No session-init.md found. Skipping Phase 0.${NC}"
fi

echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Iteration $i of $MAX_ITERATIONS${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

  # Show upcoming story info
  STORY_INFO=$(get_current_story_info "$PRD_FILE")
  echo -e "${BLUE}  Upcoming: $STORY_INFO${NC}"

  # ═══════════════════════════════════════════════════════════
  # PHASE 1: GRANDMA PRE-FLIGHT CHECK
  # ═══════════════════════════════════════════════════════════
  echo ""
  echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  Phase 1: Grandma Pre-flight Check${NC}"
  echo -e "${YELLOW}  Model: Opus 4.5${NC}"
  echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"

  # Grandma pre-flight (always on Opus 4.5)
  PREFLIGHT_PROMPT=$(cat "$SCRIPT_DIR/grandma-preflight.md")
  PREFLIGHT_OUTPUT=$(claude --model "$GRANDMA_MODEL" --dangerously-skip-permissions --print "$PREFLIGHT_PROMPT" 2>&1 | tee /dev/stderr) || true

  # Check if Grandma says to pause before starting
  if echo "$PREFLIGHT_OUTPUT" | grep -q "<grandma>PAUSE</grandma>"; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Grandma Pre-flight: HOLD UP!${NC}"
    echo -e "${RED}  High divergence risk detected before starting.${NC}"
    echo -e "${RED}  Check guidance.txt for details.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    exit 1
  fi

  echo -e "${GREEN}Pre-flight complete. Proceeding with Ralph...${NC}"

  # ═══════════════════════════════════════════════════════════
  # PHASE 2: RALPH IMPLEMENTATION
  # ═══════════════════════════════════════════════════════════
  echo ""
  echo -e "${GREEN}───────────────────────────────────────────────────────────${NC}"
  echo -e "${GREEN}  Phase 2: Ralph Implementation${NC}"

  # Determine Ralph's model based on story complexity
  RALPH_MODEL=$(get_ralph_model "$PRD_FILE")
  echo -e "${GREEN}  Model: $RALPH_MODEL${NC}"
  echo -e "${GREEN}───────────────────────────────────────────────────────────${NC}"

  # Read the prompt file
  RALPH_PROMPT=$(cat "$SCRIPT_DIR/prompt-supervised.md")

  # Ralph does his work with complexity-appropriate model
  RALPH_OUTPUT=$(claude --model "$RALPH_MODEL" --dangerously-skip-permissions --print "$RALPH_PROMPT" 2>&1 | tee /dev/stderr) || true

  # Check if Ralph says all done
  if echo "$RALPH_OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Ralph completed all tasks!${NC}"
    echo -e "${GREEN}  Finished at iteration $i of $MAX_ITERATIONS${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    exit 0
  fi

  # ═══════════════════════════════════════════════════════════
  # PHASE 3: GRANDMA POST-ITERATION REVIEW
  # ═══════════════════════════════════════════════════════════
  echo ""
  echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  Phase 3: Grandma Post-Review${NC}"
  echo -e "${YELLOW}  Model: Opus 4.5${NC}"
  echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"

  # Grandma reviews (always on Opus 4.5)
  GRANDMA_PROMPT=$(cat "$SCRIPT_DIR/grandma-review.md")
  GRANDMA_OUTPUT=$(claude --model "$GRANDMA_MODEL" --dangerously-skip-permissions --print "$GRANDMA_PROMPT" 2>&1 | tee /dev/stderr) || true

  # Check if Grandma says to pause
  if echo "$GRANDMA_OUTPUT" | grep -q "<grandma>PAUSE</grandma>"; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Grandma Post-Review: HOLD UP!${NC}"
    echo -e "${RED}  Something needs human attention.${NC}"
    echo -e "${RED}  Check guidance.txt for details.${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════${NC}"
    exit 1
  fi

  # Check if Grandma says things look good
  if echo "$GRANDMA_OUTPUT" | grep -q "<grandma>CONTINUE</grandma>"; then
    echo -e "${GREEN}Grandma approves. Continuing...${NC}"
  fi

  echo ""
  echo -e "${BLUE}Iteration $i complete. Moving to next...${NC}"
  sleep 2
done

echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Ralph reached max iterations ($MAX_ITERATIONS)${NC}"
echo -e "${YELLOW}  Not all tasks completed. Check progress.txt${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
exit 1
