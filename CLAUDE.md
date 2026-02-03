# Ralph-Claude

## What This Is

An autonomous AI agent loop that runs Claude Code repeatedly to complete product requirements until they're all done. Designed for developers who want to delegate multi-story feature work to AI while they sleep. The system breaks features into small stories, implements them one at a time with a fresh context each iteration, and uses a supervisor agent (Grandma) to catch problems between iterations.

## Architecture

### Core Abstractions

1. **Ralph** - The autonomous worker. Gets a fresh Claude Code context each iteration, reads guidance files, implements ONE story, commits if quality checks pass.
2. **Grandma** - The supervisor. Runs before (pre-flight) and after (post-review) each Ralph iteration. Uses Opus for sophisticated analysis. Can PAUSE the loop if something needs human attention.
3. **Session Init** - Phase 0. Checks environment health, git state, dependencies. Creates reproducible setup script. Runs once per session using Haiku.
4. **prd.json** - The input contract. Defines project name, branch, user stories with acceptance criteria, and complexity ratings that determine which model Ralph uses.
5. **Memory Files** - progress.txt (cumulative learnings), guidance.txt (Grandma's current notes), session-state.txt (environment health). These ARE Ralph's memory since each iteration starts with a fresh context.

### Data Flow

```
prd.json (stories) + guidance.txt (Grandma's notes) + progress.txt (learnings)
  → Phase 0: Session Init (once) - verify environment
  → Phase 1: Grandma Pre-flight - check branch drift, data model consistency
  → Phase 2: Ralph implements ONE story (model selected by complexity)
  → Phase 2.5: Test gate - runs test suite, retries if failures
  → Phase 3: Grandma Post-review - verify implementation exists, quality checks
  → Loop back to Phase 1 for next story
```

### Load-Bearing Walls

- **One story per iteration** - Stories MUST be completable in a single Claude context window. Breaking this assumption means stories get half-done with no recovery.
- **PAUSE by default** - The loop only continues on explicit `<grandma>CONTINUE</grandma>` signal. This is the safety mechanism.
- **Memory lives in files** - Ralph has NO memory between iterations. Everything persists through prd.json, progress.txt, guidance.txt, and git history. If these files are wrong, Ralph is lost.
- **Grandma is always Opus** - The supervisor needs the strongest model to catch issues. Using a weaker model for Grandma defeats the safety system.

### Grain of the Codebase

- **Easy to change:** Story content in prd.json, prompt text in markdown files, model selection per complexity level, timeouts, test commands.
- **Structural:** The 4-phase loop structure, the PAUSE/CONTINUE signal protocol, the file-based memory system, the separation between Ralph and Grandma roles.

## Decisions

### Fresh Context Each Iteration
- **Chose:** Wipe Ralph's context between stories
- **Over:** Maintaining a long-running session
- **Because:** Long sessions accumulate confusion and hallucination. Fresh context + file-based memory is more reliable than trying to preserve state in-context.
- **Revisit if:** Claude gets significantly better at long contexts.

### Grandma Pre-flight AND Post-review
- **Chose:** Two Grandma phases (before and after Ralph)
- **Over:** Post-review only
- **Because:** Pre-flight catches problems BEFORE Ralph starts (branch drift, data model conflicts). Post-review catches problems AFTER (phantom completions, test failures). Both are needed.
- **Revisit if:** Pre-flight becomes so reliable that post-review rarely finds issues.

### Dynamic Model Selection by Complexity
- **Chose:** `low`=Haiku, `medium`=Sonnet, `high`=Opus per story
- **Over:** Single model for all stories
- **Because:** Cost optimization. Simple CRUD doesn't need Opus. Default is medium (Sonnet) if unspecified.
- **Revisit if:** Pricing changes or Haiku becomes unreliable for simple tasks.

### Bash-Based Orchestrator
- **Chose:** 1156-line Bash script (`ralph-supervised-v2.sh`)
- **Over:** Node.js or Python orchestrator
- **Because:** Zero dependencies, runs anywhere Claude Code runs, easy to copy into any project. Bash is the right tool for "run commands in sequence and check exit codes."
- **Revisit if:** Orchestration logic gets complex enough to need data structures.

## Current State

### Stable
- `ralph-supervised-v2.sh` - Clean v2 rewrite, production-ready
- 4-phase loop (session init → pre-flight → implementation → test gate → post-review)
- Dynamic model selection by story complexity
- prd.json format with testing configuration
- Skills (PRD converter, PRD validator, flutter-expert)
- Logging, resume capability, archive system

### In Flux
- Testing gate (Phase 2.5) - recently added, needs more real-world usage
- design-spec.json support - added for AppFactory integration, not fully exercised
- Testing configuration in prd.json - new feature, edge cases in retry logic

### Fragile
- Session init can fail (see guidance.txt - paused at iteration 0 on Jan 17)
- Phantom completion detection - Grandma now checks for this but edge cases remain
- Signal parsing (`<grandma>CONTINUE</grandma>`) - recently improved to handle whitespace variations

### Known Debt
- No Puppeteer/browser testing integration (referenced in prompts, not exercised)
- Error recovery from mid-iteration crashes is manual (resume helps but doesn't auto-fix)
- Documentation could better explain the signal protocol

## Project-Specific Conventions

- Bash for orchestration, Markdown for prompts
- Designed to be copied INTO other projects (not used as a dependency)
- prd.json is the API contract between humans and Ralph
- All file I/O uses simple text files (no database, no API)
