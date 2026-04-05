# Elly Mobile App - Claude Code Project Guide

## Project Overview

Elly Mobile App is a React Native (Expo) mobile admin panel application that mirrors and extends the functionality of the [Elly Admin Panel](https://github.com/huseyindol/elly-admin-panel). It provides mobile-first management of pages, components, widgets, banners, and posts.

## Team Structure

### Team Lead: Claude (Orchestrator)
The **Team Lead** agent owns this project. It:
- Decomposes tasks into parallel workstreams
- Assigns subtasks to specialist agents
- Reviews and integrates all agent outputs
- Makes architectural decisions
- Owns the final commit & push

**Team Lead rule**: Before starting any feature, the Team Lead must:
1. Read the relevant section of CLAUDE.md
2. Create a TodoWrite task list
3. Spawn parallel agents for independent subtasks
4. Integrate results before committing

### Specialist Agents
- **ui-agent**: Handles screens, components, styling (React Native + NativeWind/StyleSheet)
- **api-agent**: Handles API integration, data fetching, state management (React Query + Zustand)
- **nav-agent**: Handles navigation structure (React Navigation / Expo Router)
- **test-agent**: Handles unit and integration tests (Jest + Testing Library)

## Architecture

```
elly-mobile-app/
├── app/                    # Expo Router screens (file-based routing)
│   ├── (auth)/             # Auth screens (login, forgot-password)
│   ├── (tabs)/             # Main tab navigator
│   │   ├── dashboard/      # Dashboard / overview
│   │   ├── pages/          # CMS page management
│   │   ├── posts/          # Blog/post management
│   │   ├── banners/        # Banner management
│   │   └── components/     # UI component library management
│   └── widgets/            # Widget configuration screens
├── components/             # Shared React Native components
│   ├── ui/                 # Base UI: Button, Card, Input, Badge, etc.
│   ├── forms/              # Form components with react-hook-form
│   └── layout/             # Layout helpers: Container, Section, etc.
├── hooks/                  # Custom React hooks
├── services/               # API service layer (axios instances, endpoints)
├── store/                  # Zustand global state
├── types/                  # TypeScript type definitions
├── utils/                  # Helper functions
├── constants/              # App constants, colors, theme
└── .claude/                # Claude Code agent & skill configuration
    ├── agents/             # Agent rule files
    └── skills/             # Reusable skill scripts
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Expo (SDK 52+) with Expo Router |
| Language | TypeScript (strict mode) |
| Styling | NativeWind (Tailwind for RN) + StyleSheet |
| Navigation | Expo Router (file-based) |
| State | Zustand + React Query (TanStack) |
| Forms | react-hook-form + zod |
| HTTP | Axios |
| Testing | Jest + React Native Testing Library |
| Linting | ESLint + Prettier |

## Coding Standards

### General
- All files in TypeScript (strict)
- No `any` types — use proper types or `unknown`
- Functional components only, no class components
- Prefer named exports over default exports (except screen files)

### Naming
- **Files**: `kebab-case.tsx` for components, `camelCase.ts` for utils/hooks
- **Components**: `PascalCase`
- **Hooks**: `use` prefix (`useAuth`, `usePosts`)
- **Types**: `PascalCase` with suffix (`PostItem`, `BannerFormData`)
- **Constants**: `SCREAMING_SNAKE_CASE`

### API Layer
- All API calls go through `services/` — never call `axios` directly in components
- Use React Query for server state, Zustand for client/UI state
- Handle loading, error, and empty states in every data-fetching component

### Component Rules
- Keep components < 150 lines; extract if larger
- Props interface defined above component
- Memoize expensive list items with `React.memo`

## Development Workflow

### Branch Strategy
- Feature branch: `claude/admin-panel-mobile-setup-BMSnZ`
- Never push directly to `main`
- Commit messages: `type(scope): description` (e.g., `feat(posts): add list screen`)

### Before Every Commit
1. `npx tsc --noEmit` — no TypeScript errors
2. `npx eslint . --max-warnings 0` — no lint warnings
3. Tests pass (if applicable)

### Agent Parallel Workflow
When implementing a new admin section (e.g., "Posts"):
1. **nav-agent** creates the route file
2. **api-agent** creates the service + types + React Query hooks (parallel with ui-agent)
3. **ui-agent** creates the screen + shared components
4. **Team Lead** integrates, reviews, commits

## Admin Panel Feature Map

These areas from the admin panel are mirrored in this app:

| Admin Panel Area | Mobile Screen | Status |
|-----------------|---------------|--------|
| Dashboard | `app/(tabs)/dashboard` | planned |
| Pages | `app/(tabs)/pages` | planned |
| Posts | `app/(tabs)/posts` | planned |
| Banners | `app/(tabs)/banners` | planned |
| Components | `app/(tabs)/components` | planned |
| Widgets | `app/widgets` | planned |
| Auth/Login | `app/(auth)/login` | planned |

## Environment Variables

Use `.env.local` (not committed):
```
EXPO_PUBLIC_API_URL=https://api.elly.com
EXPO_PUBLIC_API_KEY=
```

Access via `process.env.EXPO_PUBLIC_*` or use `constants/env.ts`.

## Key Commands

```bash
bun start                   # Start dev server (expo start)
bun run ios                 # iOS simulator
bun run android             # Android emulator
bunx tsc --noEmit           # Type check
bunx eslint .               # Lint
bun test                    # Run tests
bunx expo export            # Production build

# Install deps
bun install
```

## Notes for Claude Agents

- **Always read CLAUDE.md first** before starting any task
- **Team Lead** must claim ownership (create TodoWrite) before delegating
- Use parallel agents for independent work (API layer + UI layer simultaneously)
- When in doubt about design, follow the admin panel's existing patterns
- Log all architectural decisions as comments at the top of the relevant file
