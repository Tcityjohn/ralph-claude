# Ralph for Claude Code

An autonomous AI agent loop that runs Claude Code repeatedly until all your product requirements are complete. Let it work while you sleep.

> Adapted from [snarktank/ralph](https://github.com/snarktank/ralph) for use with Claude Code (Anthropic's CLI).

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    ralph-claude.sh                       │
│                                                         │
│  for each iteration:                                    │
│    1. Read prd.json → find next incomplete story        │
│    2. Spawn fresh Claude Code instance                  │
│    3. Claude implements the story                       │
│    4. Run quality checks (typecheck, lint, test)        │
│    5. Commit changes, mark story as complete            │
│    6. Update progress.txt with learnings                │
│    7. Repeat until all stories pass                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

Each iteration gets a **fresh Claude Code context**. Memory persists only through:
- Git commits (the actual code)
- `progress.txt` (learnings and patterns)
- `CLAUDE.md` files (codebase conventions)
- `prd.json` (task status)

## Prerequisites

1. **Claude Code CLI** installed and authenticated
   ```bash
   # Install Claude Code if you haven't
   npm install -g @anthropic-ai/claude-code

   # Authenticate
   claude auth
   ```

2. **jq** for JSON processing
   ```bash
   brew install jq  # macOS
   # or: apt install jq  # Linux
   ```

3. A **git repository** for your project

## Where Ralph Lives

You have two options:

### Option 1: Per-Project (Recommended for beginners)

Copy Ralph into each project that uses it:

```bash
# From your project root
mkdir -p scripts/ralph
cp ~/ralph-claude/ralph-claude.sh scripts/ralph/
cp ~/ralph-claude/prompt-claude.md scripts/ralph/
```

Then your project structure looks like:
```
my-project/
├── scripts/
│   └── ralph/
│       ├── ralph-claude.sh    # The loop script
│       ├── prompt-claude.md   # Instructions for Claude
│       ├── prd.json           # Your task list (you create this)
│       └── progress.txt       # Auto-generated learnings
├── src/
├── CLAUDE.md                  # Your codebase conventions
└── ...
```

Run it from your project:
```bash
./scripts/ralph/ralph-claude.sh
```

### Option 2: Global Installation

Keep Ralph in one place and run it from any project:

```bash
# Ralph stays at ~/ralph-claude/
# Run from any project directory:
~/ralph-claude/ralph-claude.sh
```

Note: With global installation, `prd.json` and `progress.txt` live in the ralph directory, not your project.

## Quick Start

### 1. Create your prd.json

In your ralph directory (e.g., `scripts/ralph/`), create `prd.json`:

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
        "Create users table with id, email, password_hash, created_at",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "complexity": "low",
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Create login form component",
      "description": "As a user, I want to log in to my account.",
      "acceptanceCriteria": [
        "Form has email and password fields",
        "Submit button calls auth API",
        "Shows error on invalid credentials",
        "Typecheck passes",
        "Verify in browser"
      ],
      "priority": 2,
      "complexity": "medium",
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Story Complexity (Model Selection)

Each story can have a `complexity` field that determines which AI model Ralph uses:

| Complexity | Model | Best For |
|------------|-------|----------|
| `"low"` | Haiku | Simple CRUD, adding fields, UI tweaks, copy changes |
| `"medium"` | Sonnet | New features, integrations, API endpoints (default) |
| `"high"` | Opus 4.5 | Architectural decisions, complex logic, security-sensitive code |

If omitted, complexity defaults to `"medium"` (Sonnet).

### 2. Create CLAUDE.md in your project root

```markdown
# Project Conventions

- We use TypeScript with strict mode
- Run `npm run typecheck` to verify types
- Run `npm test` to run tests
- Use Tailwind CSS for styling
```

### 3. Run Ralph

```bash
# Run with default 10 iterations
./scripts/ralph/ralph-claude.sh

# Or specify max iterations
./scripts/ralph/ralph-claude.sh 20
```

### 4. Watch it work

Ralph will:
- Pick the first incomplete story (US-001)
- Implement it
- Run your quality checks
- Commit the changes
- Mark US-001 as `passes: true`
- Move to US-002
- Continue until all stories pass or max iterations reached

## Supervised Mode (Recommended)

For better oversight, use `ralph-supervised.sh` which adds Grandma - a supervisor agent that reviews Ralph's work:

```bash
./ralph-supervised.sh [max_iterations]
```

### 3-Phase Iteration Loop

```
Each iteration runs 3 phases:

┌─────────────────────────────────────────────────────────────┐
│ Phase 1: GRANDMA PRE-FLIGHT (Opus 4.5)                      │
│   - Checks git diff from main (drift detection)             │
│   - Validates data models and types                         │
│   - Writes warnings to guidance.txt                         │
│   - Can PAUSE before Ralph starts if risk is high           │
├─────────────────────────────────────────────────────────────┤
│ Phase 2: RALPH IMPLEMENTATION (Haiku/Sonnet/Opus)           │
│   - Reads pre-flight warnings from guidance.txt             │
│   - Implements the next incomplete story                    │
│   - Model selected based on story complexity                │
├─────────────────────────────────────────────────────────────┤
│ Phase 3: GRANDMA POST-REVIEW (Opus 4.5)                     │
│   - Reviews what Ralph just did                             │
│   - Updates guidance.txt with corrections                   │
│   - Can PAUSE if something needs human attention            │
└─────────────────────────────────────────────────────────────┘
```

### Why Supervised Mode?

- **Catches divergence early**: Grandma checks if the branch has drifted from main before Ralph starts
- **Prevents compounding mistakes**: Problems get caught after each iteration, not after 10
- **Dynamic model selection**: Simple tasks use cheap/fast Haiku, complex tasks get Opus 4.5
- **Human-in-the-loop**: Grandma can PAUSE and alert you when something needs attention

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

## Files Reference

| File | Purpose |
|------|---------|
| `ralph-claude.sh` | Basic loop script (no supervision) |
| `ralph-supervised.sh` | **Recommended** - Loop with Grandma supervision |
| `prompt-claude.md` | Instructions for basic Ralph |
| `prompt-supervised.md` | Instructions for supervised Ralph |
| `grandma-preflight.md` | Grandma's pre-flight check instructions |
| `grandma-review.md` | Grandma's post-iteration review instructions |
| `prd.json` | Your task list with pass/fail status and complexity |
| `progress.txt` | Cumulative learnings (auto-generated) |
| `guidance.txt` | Grandma's guidance for Ralph (auto-generated) |
| `CLAUDE.md` | Your project conventions (Claude reads this automatically) |

## Troubleshooting

### Claude Code not found
```bash
# Make sure it's installed globally
npm install -g @anthropic-ai/claude-code

# Or check your PATH
which claude
```

### jq not found
```bash
brew install jq  # macOS
apt install jq   # Ubuntu/Debian
```

### Permission denied
```bash
chmod +x scripts/ralph/ralph-claude.sh
```

### Stories not completing
- Make sure stories are small enough for one context window
- Check that quality checks (typecheck, lint, test) are passing
- Review `progress.txt` for errors from previous iterations

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

## Original Project

This is adapted from [snarktank/ralph](https://github.com/snarktank/ralph), which was built for Amp (Sourcegraph's AI coding CLI). This version replaces Amp with Claude Code.
