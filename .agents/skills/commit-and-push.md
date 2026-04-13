# Skill: commit-and-push

## Purpose
Run pre-commit checks, create a semantic commit, and push to the feature branch.

## Usage
```
/commit-and-push "<type>(<scope>): <description>"
# Example: /commit-and-push "feat(posts): add post list screen"
```

## Steps

### 1. Pre-commit Checks
```bash
bunx tsc --noEmit                 # Must have 0 errors
bunx eslint . --max-warnings 0    # Must have 0 warnings
```
If either fails → STOP. Fix errors before committing.

### 2. Stage Files
```bash
git add <specific-files>   # Never use git add -A blindly
```

### 3. Commit
```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

https://claude.ai/code/session_011EgiL7WLiAvBaWhLyZHwUM
EOF
)"
```

### 4. Push
```bash
git push -u origin claude/admin-panel-mobile-setup-BMSnZ
```

## Commit Types
| Type | When to use |
|------|------------|
| `feat` | New feature or screen |
| `fix` | Bug fix |
| `chore` | Config, deps, tooling |
| `refactor` | Code restructure (no behavior change) |
| `docs` | CLAUDE.md, comments, README |
| `test` | Tests only |
| `style` | Formatting, NativeWind classes |

## Rules
- NEVER commit `.env.local` or any secrets
- NEVER use `--no-verify`
- NEVER push to `main` directly
- Always target: `claude/admin-panel-mobile-setup-BMSnZ`
