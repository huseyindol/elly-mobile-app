# Elly Mobile App — Agent guide (Cursor & general)

This file is the **shared entry point** for AI assistants (Cursor, Claude Code, other agents). It points to the canonical project guide and the specialist role definitions.

## Read order

1. **`CLAUDE.md`** — project overview, architecture, tech stack, coding standards, workflows, commands.
2. **This file** — where agent definitions live and how they map to tools.
3. **Role files** — pick the specialist that matches the work (see below).

## Where configuration lives

| Location | Purpose |
|----------|---------|
| `CLAUDE.md` | Single source of truth for conventions and workflows. |
| `.claude/agents/` | Specialist prompts for **Claude Code** (`team-lead`, `ui-agent`, `api-agent`, `nav-agent`, `test-agent`). |
| `.claude/skills/` | Repeatable workflows: `commit-and-push`, `new-admin-section`, `review-section`. |
| `.agents/agents/` | **Mirror** of `.claude/agents/` for Cursor and other tools that read `.agents/`. |
| `.agents/skills/` | **Mirror** of `.claude/skills/`. |
| `.cursor/rules/*.mdc` | Cursor-specific rules (optional; use for globs / always-on policies). |

**Parity rule:** `.agents` is kept in sync with `.claude`. When you add or change an agent or skill, update **both** trees (or copy from one to the other) so every tool sees the same instructions.

## Specialist roles (orchestration)

Use these labels when splitting work across subtasks or sessions:

| Role | Owns | Definition file (same in both trees) |
|------|------|----------------------------------------|
| **Team Lead** | Decomposition, parallel work, integration, pre-commit checks | `agents/team-lead.md` |
| **ui-agent** | Screens, components, NativeWind/StyleSheet, UX states | `agents/ui-agent.md` |
| **api-agent** | `services/`, `types/`, React Query hooks, Zustand data concerns | `agents/api-agent.md` |
| **nav-agent** | Expo Router layouts, routes, params, auth guard wiring | `agents/nav-agent.md` |
| **test-agent** | Jest, Testing Library, mocks, coverage | `agents/test-agent.md` |

**Team Lead checklist (any tool):**

1. Read the relevant section of `CLAUDE.md`.
2. Track subtasks with the environment’s task list (e.g. Cursor’s todo list).
3. Run independent streams in parallel when safe (often **api-agent** + **ui-agent**).
4. Integrate, then run `bunx tsc --noEmit` and `bunx eslint . --max-warnings 0` before commit.

## Skills (workflows)

| Skill | File | Summary |
|-------|------|---------|
| Commit & push | `skills/commit-and-push.md` | Pre-commit checks, semantic commit, branch push rules. |
| New admin section | `skills/new-admin-section.md` | Scaffold list + detail for a resource across nav, API, UI. |
| Review section | `skills/review-section.md` | Quality checklist before merge. |

Paths above are relative to **either** `.claude/` or `.agents/` (content is mirrored).

## Cursor-specific notes

- Prefer **project rules** in `.cursor/rules/` for always-on or path-scoped policies; keep them short and actionable.
- For multi-step features, follow the **Agent Parallel Workflow** in `CLAUDE.md` and the **Team Lead** / **new-admin-section** skill.

## Notes

- Route layout in docs may reference `app/(tabs)/`; the repo may use `app/(drawer)/` or other groups — follow the **actual** `app/` tree when implementing.
- Never commit secrets; use `.env.local` (see `CLAUDE.md`).
