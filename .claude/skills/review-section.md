# Skill: review-section

## Purpose
Review an admin section implementation for quality, consistency, and completeness before merging.

## Usage
```
/review-section <resource-name>
# Example: /review-section posts
```

## Checklist

### TypeScript
- [ ] No `any` types in `types/<resource>.ts`, `services/`, `hooks/`
- [ ] All props interfaces defined
- [ ] `npx tsc --noEmit` passes

### API Layer
- [ ] `services/<resource>.ts` covers all CRUD operations
- [ ] Response types are properly typed
- [ ] Error handling present (try/catch or error boundaries)

### Hooks
- [ ] `staleTime` set on all `useQuery` calls
- [ ] `queryKey` uses `as const` tuple
- [ ] Mutations invalidate related queries on success

### UI Screens
- [ ] Loading state shown
- [ ] Error state shown with retry option
- [ ] Empty state shown when list is empty
- [ ] Pull-to-refresh implemented on list screens
- [ ] Components < 150 lines (extract if larger)

### Navigation
- [ ] Route file exists in `app/(tabs)/<resource>/`
- [ ] Tab icon added to `app/(tabs)/_layout.tsx`
- [ ] Dynamic params typed with `useLocalSearchParams`

### Tests
- [ ] Hook tests cover loading/error/success/empty
- [ ] Card component renders correctly

### Code Style
- [ ] `npx eslint . --max-warnings 0` passes
- [ ] NativeWind classes used for styling
- [ ] Named exports (except screen default exports)

## Output Format
Report issues as:
```
[BLOCKING] <description> — <file>:<line>
[WARNING]  <description> — <file>:<line>
[SUGGEST]  <description> — <file>:<line>
```
