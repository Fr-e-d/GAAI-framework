// ── Normalization utilities for scoring engine ──────────────────────────────
// Skill aliases, industry proximity, timeline parsing (DEC-49)

// ── Skill normalization ─────────────────────────────────────────────────────

const SKILL_ALIASES: Record<string, string> = {
  'react.js': 'react',
  'reactjs': 'react',
  'node.js': 'nodejs',
  'vue.js': 'vue',
  'vuejs': 'vue',
  'next.js': 'nextjs',
  'nuxt.js': 'nuxtjs',
  'ts': 'typescript',
  'js': 'javascript',
  'py': 'python',
  'python3': 'python',
  'gpt-4': 'gpt4',
  'gpt-4o': 'gpt4o',
  'open ai': 'openai',
  'chat gpt': 'chatgpt',
  'chatgpt': 'chatgpt',
  'langchain.js': 'langchain',
  'express.js': 'express',
  'expressjs': 'express',
  'angular.js': 'angular',
  'angularjs': 'angular',
  'svelte.js': 'svelte',
};

export function normalizeSkill(skill: string): string {
  const key = skill.toLowerCase().trim();
  return SKILL_ALIASES[key] ?? key;
}

// ── Industry proximity ──────────────────────────────────────────────────────

// Keys are sorted alphabetically: "a|b" where a < b
const INDUSTRY_PROXIMITY: Record<string, number> = {
  'ai|machine-learning': 0.9,
  'banking|fintech': 0.8,
  'e-commerce|retail': 0.9,
  'edtech|education': 0.9,
  'fintech|insurtech': 0.7,
  'healthtech|medtech': 0.85,
  'logistics|supply-chain': 0.8,
  'saas|software': 0.85,
};

export function getIndustryProximity(a: string, b: string): number {
  const la = a.toLowerCase().trim();
  const lb = b.toLowerCase().trim();
  if (la === lb) return 1;
  const key = la < lb ? `${la}|${lb}` : `${lb}|${la}`;
  return INDUSTRY_PROXIMITY[key] ?? 0;
}

// ── Timeline parsing ────────────────────────────────────────────────────────

const TIMELINE_LOOKUP: Record<string, number> = {
  'urgent': 7,
  'asap': 7,
  '1 week': 7,
  '2 weeks': 14,
  '3 weeks': 21,
  '1 month': 30,
  '2 months': 60,
  '3 months': 90,
  '4 months': 120,
  '6 months': 180,
  '1 year': 365,
};

const FLEXIBLE_VALUES = new Set(['flexible', 'no rush', 'no deadline', 'whenever']);

const TIMELINE_REGEX = /^(\d+)\s*(days?|weeks?|months?|years?)$/i;

export function parseTimelineDays(timeline: string): number | null {
  const normalized = timeline.toLowerCase().trim();

  if (FLEXIBLE_VALUES.has(normalized)) return Infinity;

  const lookupResult = TIMELINE_LOOKUP[normalized];
  if (lookupResult !== undefined) return lookupResult;

  const match = TIMELINE_REGEX.exec(normalized);
  if (match && match[1] && match[2]) {
    const value = parseInt(match[1], 10);
    const unit = match[2].toLowerCase().replace(/s$/, '');
    switch (unit) {
      case 'day': return value;
      case 'week': return value * 7;
      case 'month': return value * 30;
      case 'year': return value * 365;
    }
  }

  return null;
}
