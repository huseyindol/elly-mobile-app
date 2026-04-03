# Skill: new-admin-section

## Purpose
Scaffold a complete new admin section (list + detail/edit) for a resource.

## Usage
```
/new-admin-section <resource-name>
# Example: /new-admin-section posts
```

## What This Skill Does
Creates all necessary files for a full admin section CRUD:

1. **Types** — `types/<resource>.ts`
2. **Service** — `services/<resource>.ts`
3. **Hooks** — `hooks/use<Resource>.ts`
4. **Screens** — `app/(tabs)/<resource>/index.tsx` + `[id].tsx`
5. **Components** — `components/ui/<Resource>Card.tsx`

## Steps

### Step 1 — nav-agent: Create route files
```
app/(tabs)/<resource>/index.tsx    ← list screen (stub)
app/(tabs)/<resource>/[id].tsx     ← detail/edit screen (stub)
```

### Step 2 — api-agent (parallel with Step 3): Data layer
```
types/<resource>.ts                ← ResourceItem, ResourceFormData, ResourceListResponse
services/<resource>.ts             ← resourceService (getList, getById, create, update, remove)
hooks/use<Resource>.ts             ← useResourceList, useResource, useCreateResource, useUpdateResource, useDeleteResource
```

### Step 3 — ui-agent (parallel with Step 2): UI layer
```
components/ui/<Resource>Card.tsx   ← List item card component
app/(tabs)/<resource>/index.tsx    ← Full list screen with loading/error/empty states
app/(tabs)/<resource>/[id].tsx     ← Detail/edit screen with form
```

### Step 4 — Team Lead: Integration
- Wire hooks into screens
- Add tab icon in `app/(tabs)/_layout.tsx`
- Verify TypeScript + lint
- Commit: `feat(<resource>): add <resource> admin section`

## Template Variables
Replace `<resource>` with lowercase (e.g., `posts`)
Replace `<Resource>` with PascalCase (e.g., `Posts`)
Replace `ResourceItem` with proper name (e.g., `PostItem`)
