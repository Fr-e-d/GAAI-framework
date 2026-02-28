# Fork & Own

GAAI is designed to be forked and adapted. This is the intended distribution model.

---

## Why Fork & Own?

GAAI is a governance layer, not a generic tool. Every project is different:
- Different tech stacks, languages, conventions
- Different team sizes and workflows
- Different quality standards and risk tolerances
- Different domain rules (regulated industries, specific architectures)

A shared community framework would be too generic to be useful for any specific project. Fork & Own means GAAI serves your project, not a hypothetical average project.

---

## How to Fork

GAAI is a GitHub template repository.

**Option 1: GitHub template**
1. Go to [github.com/gaai-framework/gaai-framework](https://github.com/gaai-framework/gaai-framework)
2. Click "Use this template"
3. Create your repository (private or public)
4. Done — you own a full copy

**Option 2: Clone**
```bash
git clone https://github.com/gaai-framework/gaai-framework.git /tmp/gaai
bash /tmp/gaai/install.sh
```

The installer copies `.gaai/` into your project. You own the files.

---

## What to Customize

Once you have GAAI in your project, adapt it:

### High-value customizations

**`contexts/memory/project/context.md`** — fill this in completely. This is the single most impactful thing you can do.

**`contexts/memory/patterns/conventions.md`** — add your team's coding conventions, naming rules, testing approach.

**`contexts/rules/orchestration.rules.md`** — tighten agent authority to match your risk tolerance.

**`contexts/rules/context-discovery.rules.md`** — define when Discovery is mandatory for your project.

### Advanced customizations

**Add domain rules** — create `contexts/rules/your-domain.rules.md` for domain-specific constraints.

**Extend memory** — add domain-specific memory files for large or complex projects.

**Modify skills** — adapt skill content to match your project's conventions. The SKILL.md format stays the same; the content is yours.

**Add skills** — GAAI ships 37 skills. Your project may need more. Follow the `SKILL.md` format (agentskills.io spec) and add to the appropriate category.

---

## Staying in Sync with Upstream

After forking, you own your copy. There is no automatic sync with the upstream GAAI repository.

If GAAI releases updates you want:
1. Review the upstream changelog
2. Manually apply relevant changes to your fork
3. Test with `health-check.sh`

Most value from GAAI is in the structure and conventions — not in constantly following upstream changes. Once your `.gaai/` folder reflects your project's knowledge, upstream updates matter less.

---

## What We Ask

GAAI is ELv2 licensed. You can do anything with your fork — the only restriction is you may not offer it as a competing hosted or managed service.

If you find bugs or documentation errors in the upstream framework, please report them at [GitHub Issues](https://github.com/gaai-framework/gaai-framework/issues).

We do not accept skill contributions or agent additions to the upstream repo — this is by design. Your customizations belong in your fork.

---

→ [Roadmap](roadmap.md)
→ [Senior Engineer Guide](../guides/senior-engineer-guide.md)
