# Ralph for Claude Code

![Ralph](ralph.webp)

An autonomous AI agent loop that runs Claude Code repeatedly until all your product requirements are complete. Let it work while you sleep.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/), adapted for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI).

## Features

- **Hybrid Architecture**: Combines Anthropic's Agent Harness patterns with Grandma supervision
- **Session Initialization**: Anthropic-style Phase 0 ensures reproducible environments
- **Supervised Mode**: Grandma agent reviews Ralph's work after each iteration
- **Pre-flight Checks**: Catches branch drift and data model divergence before work starts
- **Dynamic Model Selection**: Uses Haiku, Sonnet, or Opus based on task complexity
- **E2E Testing**: Puppeteer MCP support for browser-level verification
- **Automatic Archiving**: Previous runs are saved when switching features

## Prerequisites

1. **Claude Code CLI** installed and authenticated
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude auth
   ```

2. **jq** for JSON processing
   ```bash
   brew install jq  # macOS
   apt install jq   # Linux
   ```

3. A **git repository** for your project

4. **Anthropic billing** - one of:
   - **API credits** (default): Set `ANTHROPIC_API_KEY` environment variable
   - **Max subscription**: Set `RALPH_USE_SUBSCRIPTION=true` to use your Claude Max plan instead of API credits

   ```bash
   # For Max plan users (recommended - included in subscription):
   export RALPH_USE_SUBSCRIPTION=true
   ./ralph-supervised.sh 40

   # For API credit users (default):
   export ANTHROPIC_API_KEY=sk-ant-...
   ./ralph-supervised.sh 40
   ```

## Quick Start

### 1. Create your prd.json

```json
{
  "project": "MyApp",
  "branchName": "ralph/my-feature",
  "description": "Add user authentication",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add users table to database",
      "description": "As a developer, I need to store user data.",
      "acceptanceCriteria": [
        "Create users table with id, email, password_hash",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "complexity": "low",
      "passes": false,
      "notes": ""
    }
  ]
}
```

### 2. Run Ralph (Supervised Mode - Recommended)

```bash
./ralph-supervised.sh [max_iterations]
```

## How It Works

### Supervised Mode (4-Phase Hybrid Loop)

This implementation combines **Anthropic's Agent Harness** patterns (structured session initialization, reproducible environments) with **Grandma supervision** (active quality gates).

```
SESSION START (runs once):
┌─────────────────────────────────────────────────────────────┐
│ Phase 0: SESSION INITIALIZATION (Haiku - cost efficient)    │
│   - Verifies environment and dependencies                   │
│   - Checks git state and branch                             │
│   - Runs basic build/test to ensure health                  │
│   - Creates session-state.txt and init.sh                   │
│   - Can BLOCK if environment is broken                      │
└─────────────────────────────────────────────────────────────┘

ITERATION LOOP (repeats per story):
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: GRANDMA PRE-FLIGHT (Opus 4.5)                      │
│   - Checks git diff from main (drift detection)             │
│   - Validates data models and types                         │
│   - Writes warnings to guidance.txt                         │
│   - Can PAUSE before Ralph starts if risk is high           │
├─────────────────────────────────────────────────────────────┤
│ Phase 2: RALPH IMPLEMENTATION (Haiku/Sonnet/Opus)           │
│   - Reads session-state.txt and guidance.txt                │
│   - Implements the next incomplete story                    │
│   - Model selected based on story complexity                │
│   - Puppeteer MCP for E2E testing (if available)            │
├─────────────────────────────────────────────────────────────┤
│ Phase 3: GRANDMA POST-REVIEW (Opus 4.5)                     │
│   - Reviews what Ralph just did                             │
│   - Updates guidance.txt with corrections                   │
│   - Can PAUSE if something needs human attention            │
└─────────────────────────────────────────────────────────────┘
```

### Why the Hybrid Approach?

This combines the best of both worlds:

| Component | Source | Benefit |
|-----------|--------|---------|
| Session initialization | Anthropic Harness | Reproducible environments, catches issues early |
| `init.sh` generation | Anthropic Harness | Any session can recreate the setup |
| Pre-flight checks | Grandma (Original) | Active risk assessment before each story |
| Dynamic model selection | Ralph (Original) | Cost efficiency (Haiku for simple, Opus for complex) |
| Post-review supervision | Grandma (Original) | Quality gates with human escalation |
| Puppeteer E2E testing | Anthropic Harness | Browser-level verification |

### Story Complexity (Model Selection)

Each story can have a `complexity` field that determines which AI model Ralph uses:

| Complexity | Model | Best For |
|------------|-------|----------|
| `"low"` | Haiku | Simple CRUD, adding fields, UI tweaks |
| `"medium"` | Sonnet | New features, integrations, API endpoints (default) |
| `"high"` | Opus 4.5 | Architectural decisions, complex logic |

If omitted, complexity defaults to `"medium"` (Sonnet).

## Files Reference

| File | Purpose |
|------|---------|
| `ralph-supervised.sh` | **Recommended** - Loop with Grandma supervision |
| `ralph-claude.sh` | Basic loop script (no supervision) |
| `session-init.md` | **New** - Anthropic-style session initialization prompt |
| `prompt-supervised.md` | Instructions for supervised Ralph |
| `prompt-claude.md` | Instructions for basic Ralph |
| `grandma-preflight.md` | Grandma's pre-flight check instructions |
| `grandma-review.md` | Grandma's post-iteration review instructions |
| `prd.json.example` | Example PRD format with complexity field |
| `story-template.md` | Template for writing stories |
| `guidance.txt.template` | Template for Grandma's guidance file |
| `init.sh.template` | **New** - Template for reproducible environment setup |
| `progress.txt` | Cumulative learnings (auto-generated) |
| `guidance.txt` | Grandma's guidance for Ralph (auto-generated) |
| `session-state.txt` | **New** - Session health status (auto-generated) |
| `init.sh` | **New** - Reproducible setup script (auto-generated) |

## Story Sizing Rules

**Critical**: Each story must complete in ONE iteration (one context window).

### Right-sized stories:
- Add a database column and migration
- Create a single UI component
- Add one API endpoint
- Fix a specific bug

### Too big (split these):
- "Build the dashboard" → Split into: data model, API, each widget
- "Add authentication" → Split into: schema, middleware, login UI, session handling

**Rule of thumb**: If you can't describe the change in 2-3 sentences, it's too big.

## Story Ordering

Stories execute in priority order. Dependencies must come first:

1. Schema/database changes
2. Backend logic / API endpoints
3. UI components that use the backend
4. Integration / polish

## Safety Notes

Ralph runs with `--dangerously-skip-permissions`, which allows Claude to:
- Read and write files
- Execute commands
- Make git commits

**Recommendations:**
- Always run on a feature branch, never main
- Review commits before pushing
- Use in a sandboxed environment for untrusted codebases
- Set reasonable iteration limits

## Debugging

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes, complexity}'

# See learnings from previous iterations
cat progress.txt

# See Grandma's guidance
cat guidance.txt

# Check session state (new)
cat session-state.txt

# Re-initialize environment (new)
./init.sh

# Check git history
git log --oneline -10
```

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

## Credits

- Original [Ralph pattern](https://ghuntley.com/ralph/) by Geoffrey Huntley
- Original [snarktank/ralph](https://github.com/snarktank/ralph) for Amp by Ryan Carson
- [Anthropic Agent Harness patterns](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) for session initialization
- Adapted for Claude Code with supervised mode, dynamic model selection, and hybrid architecture
