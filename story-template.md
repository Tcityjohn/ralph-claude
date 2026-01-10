# Story Template for Ralph

Use this template to write tasks for Ralph. Fill it out in plain English - I'll convert it to prd.json for you.

---

## Project Info (fill once per feature)

**Project name:** [What's the app/project called?]

**Feature name:** [What are we building? e.g., "User Authentication", "Dark Mode", "Search"]

**Branch name:** [Optional - I'll generate one like `ralph/feature-name` if you skip this]

---

## Stories (one per task)

Copy this block for each task:

```
### Story: [Short title - what's being done]

**Who needs it:** [Who benefits? e.g., "users", "admins", "developers"]

**What they want:** [What should exist when this is done?]

**Why it matters:** [Optional - context for why this task exists]

**Complexity:** [low / medium / high - see guide below]

**How to verify it's done:**
- [ ] [First thing to check]
- [ ] [Second thing to check]
- [ ] [etc.]

**Depends on:** [Does another story need to finish first? Leave blank if none]

**Notes:** [Optional - anything Ralph should know]
```

### Complexity Guide (determines which AI model Ralph uses)

| Complexity | Model | Use When |
|------------|-------|----------|
| **low** | Haiku (fast, cheap) | Simple CRUD, adding fields, UI tweaks, copy changes, straightforward migrations |
| **medium** | Sonnet (balanced) | New features, integrations, components with state, API endpoints, multi-file changes |
| **high** | Opus 4.5 (powerful) | Architectural decisions, complex business logic, security-sensitive code, performance optimization |

**When in doubt, use medium.** Ralph will default to medium if you don't specify.

---

## Example: Adding a "Remember Me" checkbox to login

```
### Story: Add remember-me checkbox to login form

**Who needs it:** Users

**What they want:** A checkbox on the login form that keeps them logged in

**Why it matters:** Users hate logging in every time they visit

**Complexity:** low (simple UI addition with minor backend change)

**How to verify it's done:**
- [ ] Checkbox appears on login form below password field
- [ ] Checkbox is unchecked by default
- [ ] When checked, login session lasts 30 days
- [ ] When unchecked, login session lasts until browser closes

**Depends on:** Nothing (login form already exists)

**Notes:** We use cookies for sessions, not localStorage
```

---

## Rules of Thumb

### Make stories small
Each story should be one thing. If you find yourself writing "and" a lot, split it up.

**Too big:** "Add user profiles with avatar upload and bio editing and social links"

**Right size:**
1. Add user profile page (display only)
2. Add avatar upload to profile
3. Add bio editing to profile
4. Add social links to profile

### Order by dependencies
Put foundation work first:
1. Database stuff (where data lives)
2. Backend stuff (logic/APIs)
3. Frontend stuff (what users see)

### Make verification specific
Vague: "Works correctly"
Specific: "Clicking Save shows 'Saved!' message and refreshes the list"

### When in doubt, add more stories
10 small stories > 3 big ones. Ralph works better with small bites.

---

## Quick Version

If the full template feels like too much, just tell me:

```
Feature: [What we're building]

Tasks:
1. [First thing to do]
2. [Second thing]
3. [Third thing]

For each task, done means: [How do we know it works?]
```

I'll ask clarifying questions and build the prd.json from there.
