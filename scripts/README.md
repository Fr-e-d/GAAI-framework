# GAAI Scripts

Utility scripts for maintaining GAAI framework infrastructure.

## Scripts

### check-and-update-skills-index.js

**Purpose:** Detect when SKILL.md files have been modified and automatically regenerate the unified skills index.

**Location:** `.gaai/core/scripts/check-and-update-skills-index.js`

**How It Works:**

1. Scans all SKILL.md files in `.gaai/core/skills/` and `.gaai/project/skills/`
2. Compares their modification times (mtime) against `.gaai/core/skills/skills-index.yaml`
3. If any SKILL.md is newer than the index:
   - Regenerates the unified index
   - Reports which skills changed
   - Returns exit code 1 (index was stale and regenerated)
4. If all SKILL.md files are older than index:
   - Reports index is current
   - Returns exit code 0 (no regeneration needed)

**Usage:**

```bash
# Manual check and regenerate if needed
node .gaai/core/scripts/check-and-update-skills-index.js

# Exit codes:
#   0 = Index is current, no changes
#   1 = Index was stale and has been regenerated
```

**Automation:**

This script is automatically invoked by the Git post-commit hook (`.git/hooks/post-commit`) after each commit. No manual invocation needed under normal circumstances.

## Git Hooks

### .git/hooks/post-commit

**Purpose:** Auto-regenerate skills index when SKILL.md files are committed.

**Trigger:** After every `git commit`

**Behavior:**

1. Checks if any SKILL.md files were modified in the commit
2. If yes:
   - Runs `check-and-update-skills-index.js`
   - If index was regenerated:
     - Adds updated index to staging
     - Amends the previous commit (transparent operation)
     - Reports to user: `(amended previous commit with updated index)`
   - If index was already current:
     - Takes no action

**Example Output:**

```
📝 Detected SKILL.md changes, checking skills index...
ℹ️  Detected modification: .gaai/core/skills/cross/idiomatique-translate/SKILL.md
🔄 Regenerating skills index...
✅ Index regenerated: 45 core + 8 project = 53 total
✅ Index updated, adding to git...
   (amended previous commit with updated index)
```

**Automation Details:**

- ✅ No user action required
- ✅ Transparent (amends happen silently if no output)
- ✅ Preserves commit history (no additional commits)
- ✅ Prevents stale index from being committed

## Workflow

### Creating a New Skill

1. Create `.gaai/{core|project}/skills/{layer}/{skill-name}/SKILL.md` with frontmatter
2. Run `git add .gaai/.../SKILL.md`
3. Run `git commit -m "..."`
4. ✅ Post-commit hook:
   - Detects SKILL.md change
   - Runs index check script
   - Regenerates unified index
   - Amends your commit to include updated index
5. Done! Index is now current.

### Modifying a Skill

1. Edit `.gaai/.../skills/.../SKILL.md` (frontmatter or content)
2. Run `git add .gaai/.../SKILL.md`
3. Run `git commit -m "..."`
4. ✅ Post-commit hook handles index update automatically

### Fallback: Manual Index Regeneration

If the hook doesn't trigger or you need to manually regenerate:

```bash
node .gaai/core/scripts/check-and-update-skills-index.js
```

Then:
```bash
git add .gaai/core/skills/skills-index.yaml
git commit -m "regenerate(gaai): update skills index"
```

## Index Consistency

The unified index at `.gaai/core/skills/skills-index.yaml`:

- **Source of truth:** Frontmatter in each SKILL.md file
- **Derived cache:** The unified YAML index
- **Update trigger:** Any SKILL.md file modification
- **Validation:** `/gaai-status` can verify index freshness

The post-commit hook ensures index is never stale at commit time.

## Troubleshooting

**Q: Hook didn't run, but I committed a SKILL.md**

A: Check that hook is executable:
```bash
ls -la .git/hooks/post-commit
# Should show: -rwxr-xr-x
```

If not executable:
```bash
chmod +x .git/hooks/post-commit
```

**Q: Index is stale even though hook exists**

A: If working with a fresh clone or git worktree:
```bash
# Make hook executable
chmod +x .git/hooks/post-commit

# Force regeneration
node .gaai/core/scripts/check-and-update-skills-index.js
```

**Q: What if Node.js isn't available?**

A: The hook fails silently (returns 0 without regenerating). Fallback:
```bash
# Use the build-skills-indices skill via CLI
/gaai-discover build-skills-indices
```

## Design Philosophy

- **Automatic over manual** — Post-commit hook handles index updates transparently
- **Transparent over surprising** — Amended commits happen silently
- **Graceful degradation** — If script fails, commit still succeeds; agents can scan directories
- **No dependencies** — Scripts use only Node.js built-ins (fs, path)
- **Fast detection** — mtime comparison is O(n) and instant
