import { Form, useActionData, useLoaderData } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState, useEffect } from "react";
import { z } from "zod";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPatch, ApiError } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import { Input } from "~/components/ui/input";
import { Textarea } from "~/components/ui/textarea";
import { Label } from "~/components/ui/label";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";

// ── Static data ─────────────────────────────────────────────────────────────

const PREDEFINED_SKILLS = [
  "n8n", "Make.com", "Zapier", "Python", "Claude (Anthropic)", "GPT-4",
  "LangChain", "React", "Docker", "TypeScript", "JavaScript",
  "PostgreSQL", "Redis", "API Integration", "Webhook automation",
  "AI Agents", "RAG", "Fine-tuning", "Vector databases",
  "Airtable", "HubSpot", "Salesforce", "Slack", "Notion",
  "Google Workspace", "Microsoft 365", "Voiceflow", "Botpress",
  "OpenAI", "Anthropic", "Mistral", "Node.js",
] as const;

const PREDEFINED_VERTICALS = [
  "Workflow Automation",
  "AI Chatbots & Conversational AI",
  "AI Integration for SaaS",
  "CRM & Sales Automation",
  "Marketing Automation",
  "Data Analytics & Reporting",
  "Document Processing",
  "Customer Support Automation",
  "Lead Generation",
  "HR & Recruitment Automation",
  "E-commerce Automation",
  "Finance & Accounting Automation",
] as const;

const LANGUAGES = [
  "Français", "English", "Deutsch", "Español", "Italiano",
  "Nederlands", "Português", "Polski", "Русский", "中文",
] as const;

const GEO_ZONES = [
  "France", "Belgique", "Suisse", "Luxembourg",
  "UK & Ireland", "Germany & DACH", "Spain & Portugal",
  "Italy", "Benelux", "Nordics", "North America",
  "Global / Remote",
] as const;

const INDUSTRIES = [
  "SaaS / Tech", "E-commerce / Retail", "Finance / Fintech",
  "Healthcare / Medtech", "Legal / LegalTech", "Education / EdTech",
  "Marketing / Agency", "Manufacturing / Industry", "Consulting",
  "Real Estate", "Logistics / Supply Chain", "Media / Publishing",
] as const;

const AVAILABILITY_OPTIONS = [
  { value: "full-time freelance", label: "Temps plein (freelance)" },
  { value: "side projects", label: "Projets annexes (evenings/weekends)" },
  { value: "2 days per week", label: "2 jours par semaine" },
  { value: "3 days per week", label: "3 jours par semaine" },
  { value: "4 days per week", label: "4 jours par semaine" },
  { value: "flexible", label: "Flexible (selon les projets)" },
] as const;

const PROJECT_STAGES = [
  { value: "exploration", label: "Exploration (idée à valider)" },
  { value: "defined scope", label: "Scope défini (prêt à lancer)" },
  { value: "urgent execution", label: "Exécution urgente" },
] as const;

const CAREER_STAGE_LABELS: Record<string, string> = {
  junior: "Junior",
  medior: "Médior",
  senior: "Senior",
  "high-ticket": "Expert premium",
};

const WORK_MODE_LABELS: Record<string, string> = {
  remote: "Remote",
  "on-site": "Sur site",
  hybrid: "Hybride",
};

// ── Types ───────────────────────────────────────────────────────────────────

type ExpertProfile = {
  id: string;
  display_name: string | null;
  headline: string | null;
  bio: string | null;
  rate_min: number | null;
  rate_max: number | null;
  availability: string | null;
  profile: Record<string, unknown> | null;
  preferences: Record<string, unknown> | null;
  admissibility_criteria: Record<string, unknown> | null;
  outcome_tags: string[] | null;
  gcal_refresh_token: string | null;
  gcal_email: string | null;
};

type GcalStatus = { connected: boolean; email?: string };

type SectionName = "identite" | "expertise" | "marche" | "admissibilite";

type ActionData =
  | { success: true; section: SectionName; milestones_unlocked?: string[] }
  | {
      success: false;
      section: SectionName;
      errors: Record<string, string[] | undefined>;
      values: Record<string, unknown>;
    };

// ── Zod schemas ─────────────────────────────────────────────────────────────

const IdentiteSchema = z.object({
  display_name: z.string().min(1, "Nom requis").max(100),
  headline: z.string().min(1, "Accroche requise").max(200),
  bio: z.string().max(2000).optional(),
});

const ExpertiseSchema = z.object({
  skills: z.array(z.string()).min(1, "Sélectionnez au moins une compétence").max(15),
  verticals: z.array(z.string()).optional(),
  rate_min: z.number({ invalid_type_error: "Tarif invalide" }).int().positive().optional(),
  rate_max: z.number({ invalid_type_error: "Tarif invalide" }).int().positive().optional(),
  outcome_tags: z.array(z.string().max(200)).max(10).optional(),
});

const MarcheSchema = z.object({
  career_stage: z.enum(["junior", "medior", "senior", "high-ticket"]),
  work_mode: z.enum(["remote", "on-site", "hybrid"]),
  availability: z.string().min(1, "Disponibilité requise"),
  budget_min: z.number().int().nonnegative().optional(),
  budget_max: z.number().int().nonnegative().optional(),
  project_stage: z.array(z.string()).optional(),
  languages: z.array(z.string()).optional(),
  geo_zones: z.array(z.string()).optional(),
  industries: z.array(z.string()).optional(),
});

const AdmissibiliteSchema = z.object({
  min_project_duration_days: z.number().int().positive().optional(),
  required_methodology: z.array(z.string()).optional(),
  excluded_verticals: z.array(z.string()).optional(),
  min_budget: z.number().int().positive().optional(),
  required_stack_overlap_min: z.number().min(0).max(1).optional(),
  custom_rules: z.array(z.string()).optional(),
});

// ── Loader ──────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(request, context.cloudflare.env);
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const [profile, gcalStatus] = await Promise.all([
    apiGet<ExpertProfile>(env, session.token, `/api/experts/${userId}/profile`).catch(() => null),
    apiGet<GcalStatus>(env, session.token, `/api/experts/${userId}/gcal/status`).catch(() => null),
  ]);

  captureEvent(env, `expert:${userId}`, "expert.profile_settings_viewed", {}).catch(() => {});

  return Response.json(
    { profile, gcalStatus, userId },
    { headers: responseHeaders },
  );
}

// ── Action ───────────────────────────────────────────────────────────────────

export async function action({ request, context }: ActionFunctionArgs) {
  const { session, responseHeaders } = await requireSession(request, context.cloudflare.env);
  const env = context.cloudflare.env;
  const userId = session.user.id;
  const token = session.token;

  const formData = await request.formData();
  const intent = String(formData.get("intent") ?? "") as SectionName;

  if (intent === "identite") {
    const raw = {
      display_name: String(formData.get("display_name") ?? "").trim(),
      headline: String(formData.get("headline") ?? "").trim(),
      bio: String(formData.get("bio") ?? "").trim() || undefined,
    };
    const parsed = IdentiteSchema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        { success: false, section: "identite" as SectionName, errors: parsed.error.flatten().fieldErrors, values: raw },
        { status: 422, headers: responseHeaders },
      );
    }
    let milestonesUnlocked: string[] = [];
    try {
      const apiRes = await apiPatch<{ milestones_unlocked?: string[] }>(env, token, `/api/experts/${userId}/profile`, {
        display_name: parsed.data.display_name,
        headline: parsed.data.headline,
        bio: parsed.data.bio ?? "",
      });
      milestonesUnlocked = apiRes?.milestones_unlocked ?? [];
    } catch (err) {
      const msg = err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        { success: false, section: "identite" as SectionName, errors: { display_name: [msg] }, values: raw },
        { status: 500, headers: responseHeaders },
      );
    }
    captureEvent(env, `expert:${userId}`, "expert.profile_section_saved", { section: "identite", fields_updated: 3 }).catch(() => {});
    return Response.json(
      { success: true, section: "identite" as SectionName, milestones_unlocked: milestonesUnlocked },
      { headers: responseHeaders },
    );
  }

  if (intent === "expertise") {
    const skillsRaw = formData.getAll("skills").map(String).filter(Boolean);
    const verticals = formData.getAll("verticals").map(String).filter(Boolean);
    const rateMinStr = String(formData.get("rate_min") ?? "").trim();
    const rateMaxStr = String(formData.get("rate_max") ?? "").trim();
    const outcomeTags = formData.getAll("outcome_tags").map(String).filter(Boolean);

    const raw = {
      skills: skillsRaw,
      verticals: verticals.length > 0 ? verticals : undefined,
      rate_min: rateMinStr ? parseInt(rateMinStr) : undefined,
      rate_max: rateMaxStr ? parseInt(rateMaxStr) : undefined,
      outcome_tags: outcomeTags.length > 0 ? outcomeTags : undefined,
    };
    const parsed = ExpertiseSchema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        { success: false, section: "expertise" as SectionName, errors: parsed.error.flatten().fieldErrors, values: raw },
        { status: 422, headers: responseHeaders },
      );
    }
    let milestonesUnlockedExpertise: string[] = [];
    try {
      const apiRes = await apiPatch<{ milestones_unlocked?: string[] }>(env, token, `/api/experts/${userId}/profile`, {
        profile: { skills: parsed.data.skills, verticals: parsed.data.verticals ?? [] },
        rate_min: parsed.data.rate_min,
        rate_max: parsed.data.rate_max,
        outcome_tags: parsed.data.outcome_tags ?? [],
      });
      milestonesUnlockedExpertise = apiRes?.milestones_unlocked ?? [];
    } catch (err) {
      const msg = err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        { success: false, section: "expertise" as SectionName, errors: { skills: [msg] }, values: raw },
        { status: 500, headers: responseHeaders },
      );
    }
    captureEvent(env, `expert:${userId}`, "expert.profile_section_saved", { section: "expertise", fields_updated: parsed.data.skills.length }).catch(() => {});
    return Response.json(
      { success: true, section: "expertise" as SectionName, milestones_unlocked: milestonesUnlockedExpertise },
      { headers: responseHeaders },
    );
  }

  if (intent === "marche") {
    const projectStage = formData.getAll("project_stage").map(String).filter(Boolean);
    const languages = formData.getAll("languages").map(String).filter(Boolean);
    const geoZones = formData.getAll("geo_zones").map(String).filter(Boolean);
    const industries = formData.getAll("industries").map(String).filter(Boolean);
    const budgetMinStr = String(formData.get("budget_min") ?? "").trim();
    const budgetMaxStr = String(formData.get("budget_max") ?? "").trim();

    const raw = {
      career_stage: String(formData.get("career_stage") ?? ""),
      work_mode: String(formData.get("work_mode") ?? ""),
      availability: String(formData.get("availability") ?? ""),
      budget_min: budgetMinStr ? parseInt(budgetMinStr) : undefined,
      budget_max: budgetMaxStr ? parseInt(budgetMaxStr) : undefined,
      project_stage: projectStage.length > 0 ? projectStage : undefined,
      languages: languages.length > 0 ? languages : undefined,
      geo_zones: geoZones.length > 0 ? geoZones : undefined,
      industries: industries.length > 0 ? industries : undefined,
    };
    const parsed = MarcheSchema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        { success: false, section: "marche" as SectionName, errors: parsed.error.flatten().fieldErrors, values: raw },
        { status: 422, headers: responseHeaders },
      );
    }
    const preferences: Record<string, unknown> = {
      career_stage: parsed.data.career_stage,
      work_mode: parsed.data.work_mode,
      availability: parsed.data.availability,
      project_stage: parsed.data.project_stage ?? [],
      languages: parsed.data.languages ?? [],
      geo_zones: parsed.data.geo_zones ?? [],
      industries: parsed.data.industries ?? [],
    };
    if (parsed.data.budget_min !== undefined || parsed.data.budget_max !== undefined) {
      preferences.budget_range = { min: parsed.data.budget_min ?? 0, max: parsed.data.budget_max ?? 0 };
    }
    try {
      await apiPatch(env, token, `/api/experts/${userId}/profile`, { preferences });
    } catch (err) {
      const msg = err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        { success: false, section: "marche" as SectionName, errors: { career_stage: [msg] }, values: raw },
        { status: 500, headers: responseHeaders },
      );
    }
    captureEvent(env, `expert:${userId}`, "expert.profile_section_saved", { section: "marche", fields_updated: 4 }).catch(() => {});
    return Response.json({ success: true, section: "marche" as SectionName }, { headers: responseHeaders });
  }

  if (intent === "admissibilite") {
    const requiredMethodology = formData.getAll("required_methodology").map(String).filter(Boolean);
    const excludedVerticals = formData.getAll("excluded_verticals").map(String).filter(Boolean);
    const customRules = formData.getAll("custom_rules").map(String).filter(Boolean);
    const minDurationStr = String(formData.get("min_project_duration_days") ?? "").trim();
    const minBudgetStr = String(formData.get("min_budget") ?? "").trim();
    const overlapStr = String(formData.get("required_stack_overlap_min") ?? "").trim();

    const raw = {
      min_project_duration_days: minDurationStr ? parseInt(minDurationStr) : undefined,
      required_methodology: requiredMethodology.length > 0 ? requiredMethodology : undefined,
      excluded_verticals: excludedVerticals.length > 0 ? excludedVerticals : undefined,
      min_budget: minBudgetStr ? parseInt(minBudgetStr) : undefined,
      required_stack_overlap_min: overlapStr ? parseFloat(overlapStr) / 100 : undefined,
      custom_rules: customRules.length > 0 ? customRules : undefined,
    };
    const parsed = AdmissibiliteSchema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        { success: false, section: "admissibilite" as SectionName, errors: parsed.error.flatten().fieldErrors, values: raw },
        { status: 422, headers: responseHeaders },
      );
    }
    try {
      await apiPatch(env, token, `/api/experts/${userId}/profile`, { admissibility_criteria: parsed.data });
    } catch (err) {
      const msg = err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        { success: false, section: "admissibilite" as SectionName, errors: { min_project_duration_days: [msg] }, values: raw },
        { status: 500, headers: responseHeaders },
      );
    }
    captureEvent(env, `expert:${userId}`, "expert.profile_section_saved", { section: "admissibilite", fields_updated: Object.values(parsed.data).filter(v => v !== undefined).length }).catch(() => {});
    return Response.json({ success: true, section: "admissibilite" as SectionName }, { headers: responseHeaders });
  }

  return Response.json(
    { success: false, section: "identite" as SectionName, errors: { _form: ["Intent invalide"] }, values: {} },
    { status: 400, headers: responseHeaders },
  );
}

// ── Helper components ────────────────────────────────────────────────────────

function FieldError({ errors, field }: { errors: Record<string, string[] | undefined>; field: string }) {
  const msgs = errors[field];
  if (!msgs?.length) return null;
  return <p className="text-sm text-destructive mt-1">{msgs[0]}</p>;
}

function HelpText({ children }: { children: React.ReactNode }) {
  return <p className="text-xs text-muted-foreground mt-1">{children}</p>;
}

function TagInput({
  name,
  values,
  onChange,
  placeholder,
  maxItems,
}: {
  name: string;
  values: string[];
  onChange: (next: string[]) => void;
  placeholder?: string;
  maxItems?: number;
}) {
  const [input, setInput] = useState("");

  function add() {
    const trimmed = input.trim();
    if (!trimmed || values.includes(trimmed) || (maxItems !== undefined && values.length >= maxItems)) return;
    onChange([...values, trimmed]);
    setInput("");
  }

  return (
    <div className="space-y-2">
      {values.map((v) => (
        <input key={v} type="hidden" name={name} value={v} />
      ))}
      <div className="flex gap-2">
        <Input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(); } }}
          placeholder={placeholder}
          className="text-sm"
        />
        <Button type="button" variant="outline" size="sm" onClick={add}>+</Button>
      </div>
      {values.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {values.map((v) => (
            <span
              key={v}
              className="inline-flex items-center gap-1 px-2 py-0.5 bg-secondary text-secondary-foreground text-xs rounded-full"
            >
              {v}
              <button
                type="button"
                onClick={() => onChange(values.filter((x) => x !== v))}
                className="hover:text-destructive ml-1"
              >×</button>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Section components ───────────────────────────────────────────────────────

function IdentiteSection({
  profile,
  actionData,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
}) {
  const errors =
    actionData && !actionData.success && actionData.section === "identite"
      ? actionData.errors
      : {};

  return (
    <Card>
      <CardHeader>
        <CardTitle>Identité</CardTitle>
        <CardDescription>Vos informations de présentation visibles par les prospects.</CardDescription>
      </CardHeader>
      <Form method="post">
        <input type="hidden" name="intent" value="identite" />
        <CardContent className="space-y-4">
          <div className="space-y-2">
            {/* AC8: Mandatory for Matchable milestone */}
            <div className="flex items-center gap-2">
              <Label htmlFor="display_name">Nom affiché *</Label>
              <span className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">Requis pour devenir matchable</span>
            </div>
            <Input
              id="display_name"
              name="display_name"
              defaultValue={profile?.display_name ?? ""}
              placeholder="Jean Dupont"
            />
            <FieldError errors={errors} field="display_name" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="headline">Accroche *</Label>
            <Input
              id="headline"
              name="headline"
              defaultValue={profile?.headline ?? ""}
              placeholder="Expert n8n & automatisation IA"
            />
            <FieldError errors={errors} field="headline" />
          </div>
          <div className="space-y-2">
            {/* AC8: Bio ≥50 chars required for Matchable milestone */}
            <div className="flex items-center gap-2">
              <Label htmlFor="bio">Bio</Label>
              <span className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">50 caractères min pour devenir matchable</span>
            </div>
            <Textarea
              id="bio"
              name="bio"
              defaultValue={profile?.bio ?? ""}
              placeholder="Décrivez votre expertise... (50 caractères minimum pour le matching)"
              rows={4}
            />
            <FieldError errors={errors} field="bio" />
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit">Enregistrer</Button>
        </CardFooter>
      </Form>
    </Card>
  );
}

function ExpertiseSection({
  profile,
  actionData,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
}) {
  const errors =
    actionData && !actionData.success && actionData.section === "expertise"
      ? actionData.errors
      : {};

  const existingSkills = (profile?.profile as Record<string, unknown> | null)?.skills as string[] ?? [];
  const existingVerticals = (profile?.profile as Record<string, unknown> | null)?.verticals as string[] ?? [];

  const [skills, setSkills] = useState<string[]>(() => existingSkills);
  const [verticals, setVerticals] = useState<string[]>(() => existingVerticals);
  const [outcomeTags, setOutcomeTags] = useState<string[]>(() => profile?.outcome_tags ?? []);

  function toggleSkill(skill: string) {
    setSkills((prev) =>
      prev.includes(skill)
        ? prev.filter((s) => s !== skill)
        : prev.length < 15
          ? [...prev, skill]
          : prev,
    );
  }

  function toggleVertical(v: string) {
    setVerticals((prev) =>
      prev.includes(v) ? prev.filter((x) => x !== v) : [...prev, v],
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Expertise</CardTitle>
        <CardDescription>Vos compétences et spécialités pour affiner le matching.</CardDescription>
      </CardHeader>
      <Form method="post">
        <input type="hidden" name="intent" value="expertise" />
        {skills.map((s) => (
          <input key={s} type="hidden" name="skills" value={s} />
        ))}
        {verticals.map((v) => (
          <input key={v} type="hidden" name="verticals" value={v} />
        ))}
        <CardContent className="space-y-6">
          {/* Skills — AC8: 3+ required for Matchable milestone */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 flex-wrap">
              <Label>Compétences * ({skills.length}/15)</Label>
              <span className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">3 minimum pour devenir matchable</span>
            </div>
            <div className="flex flex-wrap gap-2 p-3 border rounded-md min-h-[60px]">
              {PREDEFINED_SKILLS.map((skill) => (
                <button
                  key={skill}
                  type="button"
                  onClick={() => toggleSkill(skill)}
                  className={[
                    "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
                    skills.includes(skill)
                      ? "bg-primary text-primary-foreground border-primary"
                      : "bg-background text-muted-foreground border-input hover:border-primary",
                  ].join(" ")}
                >
                  {skill}
                </button>
              ))}
            </div>
            {skills.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-1">
                {skills.filter((s) => !PREDEFINED_SKILLS.includes(s as typeof PREDEFINED_SKILLS[number])).map((s) => (
                  <span
                    key={s}
                    className="inline-flex items-center gap-1 px-2 py-0.5 bg-primary/10 text-primary text-xs rounded-full"
                  >
                    {s}
                    <button
                      type="button"
                      onClick={() => setSkills((prev) => prev.filter((x) => x !== s))}
                      className="hover:text-destructive"
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>
            )}
            <FieldError errors={errors} field="skills" />
          </div>

          {/* Verticals */}
          <div className="space-y-2">
            <Label>Secteurs d'activité</Label>
            <div className="grid grid-cols-2 gap-2">
              {PREDEFINED_VERTICALS.map((v) => (
                <label key={v} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="checkbox"
                    checked={verticals.includes(v)}
                    onChange={() => toggleVertical(v)}
                    className="h-4 w-4"
                  />
                  {v}
                </label>
              ))}
            </div>
          </div>

          {/* Rate */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="rate_min">Tarif min (€/h)</Label>
              <Input
                id="rate_min"
                name="rate_min"
                type="number"
                min={0}
                defaultValue={profile?.rate_min?.toString() ?? ""}
                placeholder="50"
              />
              <FieldError errors={errors} field="rate_min" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="rate_max">Tarif max (€/h)</Label>
              <Input
                id="rate_max"
                name="rate_max"
                type="number"
                min={0}
                defaultValue={profile?.rate_max?.toString() ?? ""}
                placeholder="150"
              />
              <FieldError errors={errors} field="rate_max" />
            </div>
          </div>

          {/* Outcome tags */}
          <div className="space-y-2">
            <Label>Résultats types ({outcomeTags.length}/10)</Label>
            <TagInput
              name="outcome_tags"
              values={outcomeTags}
              onChange={setOutcomeTags}
              placeholder="Ex: 25h/semaine économisées sur le traitement RFP"
              maxItems={10}
            />
            <FieldError errors={errors} field="outcome_tags" />
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit">Enregistrer</Button>
        </CardFooter>
      </Form>
    </Card>
  );
}

function MarcheSection({
  profile,
  actionData,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
}) {
  const errors =
    actionData && !actionData.success && actionData.section === "marche"
      ? actionData.errors
      : {};

  const existingPrefs = profile?.preferences as Record<string, unknown> | null;
  const existingBudget = existingPrefs?.budget_range as { min?: number; max?: number } | undefined;

  const [selectedProjectStages, setSelectedProjectStages] = useState<string[]>(
    () => (existingPrefs?.project_stage as string[]) ?? [],
  );
  const [selectedLanguages, setSelectedLanguages] = useState<string[]>(
    () => (existingPrefs?.languages as string[]) ?? [],
  );
  const [selectedGeoZones, setSelectedGeoZones] = useState<string[]>(
    () => (existingPrefs?.geo_zones as string[]) ?? [],
  );
  const [selectedIndustries, setSelectedIndustries] = useState<string[]>(
    () => (existingPrefs?.industries as string[]) ?? [],
  );

  function toggle(
    list: string[],
    setList: React.Dispatch<React.SetStateAction<string[]>>,
    value: string,
  ) {
    setList((prev) =>
      prev.includes(value) ? prev.filter((x) => x !== value) : [...prev, value],
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Positionnement marché</CardTitle>
        <CardDescription>Vos préférences de travail et critères de sélection des projets.</CardDescription>
      </CardHeader>
      <Form method="post">
        <input type="hidden" name="intent" value="marche" />
        {selectedProjectStages.map((s) => (
          <input key={s} type="hidden" name="project_stage" value={s} />
        ))}
        {selectedLanguages.map((l) => (
          <input key={l} type="hidden" name="languages" value={l} />
        ))}
        {selectedGeoZones.map((g) => (
          <input key={g} type="hidden" name="geo_zones" value={g} />
        ))}
        {selectedIndustries.map((i) => (
          <input key={i} type="hidden" name="industries" value={i} />
        ))}
        <CardContent className="space-y-6">
          {/* Career stage */}
          <div className="space-y-2">
            <Label>Positionnement *</Label>
            <div className="grid grid-cols-2 gap-2">
              {(
                [
                  { value: "junior", label: "Junior (< 2 ans)" },
                  { value: "medior", label: "Confirmé (2–5 ans)" },
                  { value: "senior", label: "Senior (5+ ans)" },
                  { value: "high-ticket", label: "Expert premium" },
                ] as const
              ).map(({ value, label }) => (
                <label key={value} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="radio"
                    name="career_stage"
                    value={value}
                    defaultChecked={(existingPrefs?.career_stage as string) === value}
                    className="h-4 w-4"
                  />
                  {label}
                </label>
              ))}
            </div>
            <FieldError errors={errors} field="career_stage" />
          </div>

          {/* Work mode */}
          <div className="space-y-2">
            <Label>Mode de travail *</Label>
            <div className="flex gap-4">
              {(
                [
                  { value: "remote", label: "Télétravail" },
                  { value: "on-site", label: "Sur site" },
                  { value: "hybrid", label: "Hybride" },
                ] as const
              ).map(({ value, label }) => (
                <label key={value} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="radio"
                    name="work_mode"
                    value={value}
                    defaultChecked={(existingPrefs?.work_mode as string) === value}
                    className="h-4 w-4"
                  />
                  {label}
                </label>
              ))}
            </div>
            <FieldError errors={errors} field="work_mode" />
          </div>

          {/* Availability */}
          <div className="space-y-2">
            <Label htmlFor="availability">Disponibilité *</Label>
            <select
              id="availability"
              name="availability"
              defaultValue={(existingPrefs?.availability as string) ?? ""}
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            >
              <option value="">Sélectionner...</option>
              {AVAILABILITY_OPTIONS.map(({ value, label }) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
            <FieldError errors={errors} field="availability" />
          </div>

          {/* Budget range */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="budget_min">Budget min accepté (€)</Label>
              <Input
                id="budget_min"
                name="budget_min"
                type="number"
                min={0}
                defaultValue={existingBudget?.min?.toString() ?? ""}
                placeholder="1000"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="budget_max">Budget max accepté (€)</Label>
              <Input
                id="budget_max"
                name="budget_max"
                type="number"
                min={0}
                defaultValue={existingBudget?.max?.toString() ?? ""}
                placeholder="50000"
              />
            </div>
          </div>

          {/* Project stage */}
          <div className="space-y-2">
            <Label>Stade du projet</Label>
            <div className="flex flex-col gap-2">
              {PROJECT_STAGES.map(({ value, label }) => (
                <label key={value} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="checkbox"
                    checked={selectedProjectStages.includes(value)}
                    onChange={() => toggle(selectedProjectStages, setSelectedProjectStages, value)}
                    className="h-4 w-4"
                  />
                  {label}
                </label>
              ))}
            </div>
          </div>

          {/* Languages */}
          <div className="space-y-2">
            <Label>Langues de travail</Label>
            <div className="flex flex-wrap gap-2">
              {LANGUAGES.map((lang) => (
                <button
                  key={lang}
                  type="button"
                  onClick={() => toggle(selectedLanguages, setSelectedLanguages, lang)}
                  className={[
                    "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
                    selectedLanguages.includes(lang)
                      ? "bg-primary text-primary-foreground border-primary"
                      : "bg-background text-muted-foreground border-input hover:border-primary",
                  ].join(" ")}
                >
                  {lang}
                </button>
              ))}
            </div>
          </div>

          {/* Geo zones */}
          <div className="space-y-2">
            <Label>Zones géographiques</Label>
            <div className="flex flex-wrap gap-2">
              {GEO_ZONES.map((zone) => (
                <button
                  key={zone}
                  type="button"
                  onClick={() => toggle(selectedGeoZones, setSelectedGeoZones, zone)}
                  className={[
                    "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
                    selectedGeoZones.includes(zone)
                      ? "bg-primary text-primary-foreground border-primary"
                      : "bg-background text-muted-foreground border-input hover:border-primary",
                  ].join(" ")}
                >
                  {zone}
                </button>
              ))}
            </div>
          </div>

          {/* Industries */}
          <div className="space-y-2">
            <Label>Secteurs d'industrie préférés</Label>
            <div className="grid grid-cols-2 gap-2">
              {INDUSTRIES.map((ind) => (
                <label key={ind} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="checkbox"
                    checked={selectedIndustries.includes(ind)}
                    onChange={() => toggle(selectedIndustries, setSelectedIndustries, ind)}
                    className="h-4 w-4"
                  />
                  {ind}
                </label>
              ))}
            </div>
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit">Enregistrer</Button>
        </CardFooter>
      </Form>
    </Card>
  );
}

function AdmissibiliteSection({
  profile,
  actionData,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
}) {
  const errors =
    actionData && !actionData.success && actionData.section === "admissibilite"
      ? actionData.errors
      : {};

  const admissibilityCriteria = profile?.admissibility_criteria as Record<string, unknown> | null;

  const [methodology, setMethodology] = useState<string[]>(
    () => (admissibilityCriteria?.required_methodology as string[]) ?? [],
  );
  const [excludedVerticals, setExcludedVerticals] = useState<string[]>(
    () => (admissibilityCriteria?.excluded_verticals as string[]) ?? [],
  );
  const [customRules, setCustomRules] = useState<string[]>(
    () => (admissibilityCriteria?.custom_rules as string[]) ?? [],
  );
  const [overlap, setOverlap] = useState<number>(() => {
    const v = (admissibilityCriteria?.required_stack_overlap_min as number | undefined) ?? 0;
    return Math.round(v * 100);
  });

  function toggleExcludedVertical(v: string) {
    setExcludedVerticals((prev) =>
      prev.includes(v) ? prev.filter((x) => x !== v) : [...prev, v],
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Critères d'admissibilité</CardTitle>
        <CardDescription>Ces critères filtrent automatiquement les prospects avant le matching.</CardDescription>
      </CardHeader>
      <Form method="post">
        <input type="hidden" name="intent" value="admissibilite" />
        {excludedVerticals.map((v) => (
          <input key={v} type="hidden" name="excluded_verticals" value={v} />
        ))}
        <CardContent className="space-y-6">
          <p className="text-sm text-muted-foreground">
            Ces critères filtrent automatiquement les prospects avant le matching. Les prospects qui ne correspondent pas ne vous seront jamais envoyés.
          </p>

          {/* Min project duration */}
          <div className="space-y-2">
            <Label htmlFor="min_project_duration_days">Durée minimale du projet (jours)</Label>
            <HelpText>Refuser les missions trop courtes. Laissez vide pour ne pas filtrer.</HelpText>
            <Input
              id="min_project_duration_days"
              name="min_project_duration_days"
              type="number"
              min={1}
              defaultValue={(admissibilityCriteria?.min_project_duration_days as number | undefined)?.toString() ?? ""}
              placeholder="30"
            />
            <FieldError errors={errors} field="min_project_duration_days" />
          </div>

          {/* Required methodology */}
          <div className="space-y-2">
            <Label>Méthodologies requises</Label>
            <HelpText>Les prospects doivent mentionner ces méthodologies dans leur brief.</HelpText>
            <TagInput
              name="required_methodology"
              values={methodology}
              onChange={setMethodology}
              placeholder="ex: agile, waterfall"
            />
            <FieldError errors={errors} field="required_methodology" />
          </div>

          {/* Excluded verticals */}
          <div className="space-y-2">
            <Label>Secteurs exclus</Label>
            <HelpText>Secteurs pour lesquels vous refusez tout projet.</HelpText>
            <div className="grid grid-cols-2 gap-2">
              {PREDEFINED_VERTICALS.map((v) => (
                <label key={v} className="flex items-center gap-2 cursor-pointer text-sm">
                  <input
                    type="checkbox"
                    checked={excludedVerticals.includes(v)}
                    onChange={() => toggleExcludedVertical(v)}
                    className="h-4 w-4"
                  />
                  {v}
                </label>
              ))}
            </div>
            <FieldError errors={errors} field="excluded_verticals" />
          </div>

          {/* Min budget */}
          <div className="space-y-2">
            <Label htmlFor="min_budget">Budget minimum du projet (€)</Label>
            <HelpText>Projets en dessous de ce montant seront automatiquement refusés.</HelpText>
            <Input
              id="min_budget"
              name="min_budget"
              type="number"
              min={0}
              defaultValue={(admissibilityCriteria?.min_budget as number | undefined)?.toString() ?? ""}
              placeholder="5000"
            />
            <FieldError errors={errors} field="min_budget" />
          </div>

          {/* Stack overlap */}
          <div className="space-y-2">
            <Label htmlFor="required_stack_overlap_min">Overlap de stack minimum : {overlap}%</Label>
            <HelpText>
              Pourcentage minimum de votre stack qui doit être mentionné dans le brief du prospect.
              0% = pas de filtre, 100% = toutes vos compétences doivent correspondre.
            </HelpText>
            <input
              type="range"
              id="required_stack_overlap_min"
              name="required_stack_overlap_min"
              min="0"
              max="100"
              step="1"
              value={overlap}
              onChange={(e) => setOverlap(Number(e.target.value))}
              className="w-full"
            />
            <span className="text-sm text-muted-foreground">{overlap}%</span>
            <FieldError errors={errors} field="required_stack_overlap_min" />
          </div>

          {/* Custom rules */}
          <div className="space-y-2">
            <Label>Règles personnalisées</Label>
            <HelpText>Critères d'exclusion libres — interprétation automatique à venir (non actif pour l'instant).</HelpText>
            <TagInput
              name="custom_rules"
              values={customRules}
              onChange={setCustomRules}
              placeholder="ex: Refus projets <3 mois"
            />
            <FieldError errors={errors} field="custom_rules" />
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit">Enregistrer</Button>
        </CardFooter>
      </Form>
    </Card>
  );
}

function GcalSection({ gcalStatus }: { gcalStatus: GcalStatus | null }) {
  const isConnected = gcalStatus?.connected ?? false;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Google Calendar</CardTitle>
        <CardDescription>Connexion pour la prise de rendez-vous automatique.</CardDescription>
      </CardHeader>
      <CardContent>
        {isConnected ? (
          <p className="text-sm text-green-600">Connecté : {gcalStatus?.email}</p>
        ) : (
          <p className="text-sm text-muted-foreground">Non connecté</p>
        )}
      </CardContent>
      <CardFooter>
        <a href="/dashboard/gcal" className="text-sm text-primary underline underline-offset-4">
          Gérer la connexion Google Calendar →
        </a>
      </CardFooter>
    </Card>
  );
}

// ── Main component ───────────────────────────────────────────────────────────

export default function SettingsPage() {
  const { profile, gcalStatus } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;

  useEffect(() => {
    if (!actionData) return;
    if (actionData.success) {
      toast.success("Profil mis à jour");
      // AC9: Celebratory toasts for newly unlocked milestones
      const milestoneLabels: Record<string, string> = {
        matchable: "Félicitations ! Vous êtes maintenant matchable. 40EUR crédités sur votre compte.",
        bookable:  "Félicitations ! Vous êtes maintenant réservable. 40EUR crédités sur votre compte.",
        trust:     "Félicitations ! Votre profil inspire confiance. 20EUR crédités sur votre compte.",
      };
      for (const milestone of actionData.milestones_unlocked ?? []) {
        const msg = milestoneLabels[milestone];
        if (msg) toast.success(msg, { duration: 6000 });
      }
    } else {
      const firstError = Object.values(actionData.errors)[0];
      toast.error(firstError?.[0] ?? "Erreur lors de la sauvegarde.");
    }
  }, [actionData]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Paramètres du profil</h1>
        <p className="text-muted-foreground mt-1">Gérez vos informations et critères de matching.</p>
      </div>
      <IdentiteSection profile={profile} actionData={actionData} />
      <ExpertiseSection profile={profile} actionData={actionData} />
      <MarcheSection profile={profile} actionData={actionData} />
      <AdmissibiliteSection profile={profile} actionData={actionData} />
      <GcalSection gcalStatus={gcalStatus} />
    </div>
  );
}

// Silence unused import warnings for CAREER_STAGE_LABELS / WORK_MODE_LABELS
// (They are defined for potential future use and to satisfy the spec.)
void CAREER_STAGE_LABELS;
void WORK_MODE_LABELS;
