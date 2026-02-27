import { Form, redirect, useActionData, useLoaderData, useNavigate } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState } from "react";
import { z } from "zod";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPatch, ApiError } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { Button } from "~/components/ui/button";
import { Input } from "~/components/ui/input";
import { Label } from "~/components/ui/label";
import { Textarea } from "~/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "~/components/ui/card";
import { Progress } from "~/components/ui/progress";

// ── Static data ────────────────────────────────────────────────────────────

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

// ── Zod schemas ─────────────────────────────────────────────────────────────

const Step1Schema = z.object({
  display_name: z.string().min(1, "Nom requis").max(100, "Max 100 caractères"),
  headline: z
    .string()
    .min(1, "Accroche requise")
    .max(200, "Max 200 caractères"),
  bio: z.string().max(2000, "Max 2000 caractères").optional(),
});

const Step2Schema = z.object({
  skills: z
    .array(z.string())
    .min(1, "Sélectionnez au moins une compétence")
    .max(15, "Maximum 15 compétences"),
  verticals: z.array(z.string()).optional(),
  rate_min: z
    .number({ invalid_type_error: "Tarif invalide" })
    .int()
    .positive("Doit être positif")
    .optional(),
  rate_max: z
    .number({ invalid_type_error: "Tarif invalide" })
    .int()
    .positive("Doit être positif")
    .optional(),
  outcome_tags: z
    .array(z.string().max(200))
    .max(10, "Maximum 10 tags")
    .optional(),
});

const Step3Schema = z.object({
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

// ── Types ───────────────────────────────────────────────────────────────────

type ExpertProfile = {
  id: string;
  display_name: string | null;
  headline: string | null;
  bio: string | null;
  rate_min: number | null;
  rate_max: number | null;
  profile: Record<string, unknown> | null;
  preferences: Record<string, unknown> | null;
  outcome_tags: string[] | null;
  gcal_refresh_token: string | null;
  gcal_email: string | null;
};

type GcalStatus = { connected: boolean; email?: string };

type LoaderData = {
  step: number;
  profile: ExpertProfile | null;
  gcalStatus: GcalStatus | null;
  userId: string;
};

type Step1Errors = Partial<Record<keyof z.infer<typeof Step1Schema>, string[]>>;
type Step2Errors = Partial<Record<keyof z.infer<typeof Step2Schema>, string[]>>;
type Step3Errors = Partial<Record<keyof z.infer<typeof Step3Schema>, string[]>>;

type ActionData =
  | { success: true }
  | {
      success: false;
      step: number;
      errors: Step1Errors | Step2Errors | Step3Errors;
      values: Record<string, unknown>;
    };

// ── Loader ──────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;

  const url = new URL(request.url);
  const stepParam = parseInt(url.searchParams.get("step") ?? "1");
  const step = isNaN(stepParam) ? 1 : Math.max(1, Math.min(4, stepParam));

  const [profile, gcalStatus] = await Promise.all([
    apiGet<ExpertProfile>(env, session.token, `/api/experts/${session.user.id}/profile`).catch(
      () => null,
    ),
    apiGet<GcalStatus>(env, session.token, `/api/experts/${session.user.id}/gcal/status`).catch(
      () => null,
    ),
  ]);

  return Response.json(
    { step, profile, gcalStatus, userId: session.user.id },
    { headers: responseHeaders },
  );
}

// ── Action ───────────────────────────────────────────────────────────────────

export async function action({ request, context }: ActionFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;
  const token = session.token;

  const formData = await request.formData();
  const stepStr = formData.get("step");
  const step = parseInt(String(stepStr)) || 1;
  const intent = String(formData.get("intent") ?? "next");

  // ── Step 4 special handling ──
  if (step === 4) {
    if (intent === "connect_gcal") {
      try {
        const { url: authUrl } = await apiGet<{ url: string }>(
          env,
          token,
          `/api/experts/${userId}/gcal/auth-url`,
        );
        return redirect(authUrl, { headers: responseHeaders });
      } catch {
        return Response.json(
          {
            success: false,
            step: 4,
            errors: {},
            values: {},
          },
          { status: 500, headers: responseHeaders },
        );
      }
    }
    // skip or complete
    await captureEvent(env, `expert:${userId}`, "expert.onboarding_completed", {
      gcal_connected: intent === "complete",
    });
    return redirect("/dashboard?welcome=1", { headers: responseHeaders });
  }

  // ── Steps 1–3: validate + PATCH ──

  if (step === 1) {
    const raw = {
      display_name: String(formData.get("display_name") ?? "").trim(),
      headline: String(formData.get("headline") ?? "").trim(),
      bio: String(formData.get("bio") ?? "").trim() || undefined,
    };

    const parsed = Step1Schema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        {
          success: false,
          step: 1,
          errors: parsed.error.flatten().fieldErrors,
          values: raw,
        },
        { status: 422, headers: responseHeaders },
      );
    }

    try {
      await apiPatch(env, token, `/api/experts/${userId}/profile`, {
        display_name: parsed.data.display_name,
        headline: parsed.data.headline,
        bio: parsed.data.bio ?? "",
      });
    } catch (err) {
      const msg =
        err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        {
          success: false,
          step: 1,
          errors: { display_name: [msg] },
          values: raw,
        },
        { status: 500, headers: responseHeaders },
      );
    }

    await captureEvent(env, `expert:${userId}`, "expert.onboarding_step_completed", {
      step: 1,
      fields_filled: Object.keys(raw).filter(
        (k) => raw[k as keyof typeof raw],
      ).length,
    });

    return redirect("/onboarding?step=2", { headers: responseHeaders });
  }

  if (step === 2) {
    const skillsRaw = formData.getAll("skills").map(String);
    const customSkill = String(formData.get("custom_skill") ?? "").trim();
    const skills = customSkill ? [...skillsRaw, customSkill] : skillsRaw;
    const verticals = formData.getAll("verticals").map(String);
    const rateMinRaw = formData.get("rate_min");
    const rateMaxRaw = formData.get("rate_max");
    const outcomeTags = formData
      .getAll("outcome_tags")
      .map(String)
      .filter(Boolean);

    const raw = {
      skills,
      verticals: verticals.length > 0 ? verticals : undefined,
      rate_min:
        rateMinRaw && String(rateMinRaw).trim()
          ? parseInt(String(rateMinRaw))
          : undefined,
      rate_max:
        rateMaxRaw && String(rateMaxRaw).trim()
          ? parseInt(String(rateMaxRaw))
          : undefined,
      outcome_tags: outcomeTags.length > 0 ? outcomeTags : undefined,
    };

    const parsed = Step2Schema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        {
          success: false,
          step: 2,
          errors: parsed.error.flatten().fieldErrors,
          values: { ...raw, skills: skillsRaw },
        },
        { status: 422, headers: responseHeaders },
      );
    }

    try {
      await apiPatch(env, token, `/api/experts/${userId}/profile`, {
        profile: { skills: parsed.data.skills, verticals: parsed.data.verticals ?? [] },
        rate_min: parsed.data.rate_min,
        rate_max: parsed.data.rate_max,
        outcome_tags: parsed.data.outcome_tags ?? [],
      });
    } catch (err) {
      const msg =
        err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        {
          success: false,
          step: 2,
          errors: { skills: [msg] },
          values: { ...raw, skills: skillsRaw },
        },
        { status: 500, headers: responseHeaders },
      );
    }

    await captureEvent(env, `expert:${userId}`, "expert.onboarding_step_completed", {
      step: 2,
      fields_filled: parsed.data.skills.length,
    });

    return redirect("/onboarding?step=3", { headers: responseHeaders });
  }

  if (step === 3) {
    const projectStage = formData.getAll("project_stage").map(String);
    const languages = formData.getAll("languages").map(String);
    const geoZones = formData.getAll("geo_zones").map(String);
    const industries = formData.getAll("industries").map(String);
    const budgetMinRaw = formData.get("budget_min");
    const budgetMaxRaw = formData.get("budget_max");

    const raw = {
      career_stage: String(formData.get("career_stage") ?? "") as
        | "junior"
        | "medior"
        | "senior"
        | "high-ticket",
      work_mode: String(formData.get("work_mode") ?? "") as
        | "remote"
        | "on-site"
        | "hybrid",
      availability: String(formData.get("availability") ?? ""),
      budget_min:
        budgetMinRaw && String(budgetMinRaw).trim()
          ? parseInt(String(budgetMinRaw))
          : undefined,
      budget_max:
        budgetMaxRaw && String(budgetMaxRaw).trim()
          ? parseInt(String(budgetMaxRaw))
          : undefined,
      project_stage: projectStage.length > 0 ? projectStage : undefined,
      languages: languages.length > 0 ? languages : undefined,
      geo_zones: geoZones.length > 0 ? geoZones : undefined,
      industries: industries.length > 0 ? industries : undefined,
    };

    const parsed = Step3Schema.safeParse(raw);
    if (!parsed.success) {
      return Response.json(
        {
          success: false,
          step: 3,
          errors: parsed.error.flatten().fieldErrors,
          values: raw,
        },
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
      preferences.budget_range = {
        min: parsed.data.budget_min ?? 0,
        max: parsed.data.budget_max ?? 0,
      };
    }

    try {
      await apiPatch(env, token, `/api/experts/${userId}/profile`, { preferences });
    } catch (err) {
      const msg =
        err instanceof ApiError ? `Erreur API: ${err.status}` : "Erreur lors de la sauvegarde.";
      return Response.json(
        {
          success: false,
          step: 3,
          errors: { career_stage: [msg] },
          values: raw,
        },
        { status: 500, headers: responseHeaders },
      );
    }

    await captureEvent(env, `expert:${userId}`, "expert.onboarding_step_completed", {
      step: 3,
      fields_filled: Object.values(parsed.data).filter(
        (v) => v !== undefined && (Array.isArray(v) ? v.length > 0 : true),
      ).length,
    });

    return redirect("/onboarding?step=4", { headers: responseHeaders });
  }

  return redirect("/onboarding?step=1", { headers: responseHeaders });
}

// ── Component helpers ────────────────────────────────────────────────────────

function StepDots({ current, total }: { current: number; total: number }) {
  return (
    <div className="flex items-center gap-2">
      {Array.from({ length: total }, (_, i) => (
        <div
          key={i}
          className={[
            "h-2 w-2 rounded-full transition-colors",
            i + 1 === current
              ? "bg-primary"
              : i + 1 < current
                ? "bg-primary/40"
                : "bg-muted",
          ].join(" ")}
        />
      ))}
      <span className="ml-2 text-xs text-muted-foreground">
        {current} / {total}
      </span>
    </div>
  );
}

function FieldError({ errors, field }: { errors: Record<string, string[] | undefined>; field: string }) {
  const msgs = errors[field];
  if (!msgs?.length) return null;
  return (
    <p className="text-sm text-destructive mt-1">{msgs[0]}</p>
  );
}

// ── Step 1: Basic Info ───────────────────────────────────────────────────────

function Step1Form({
  profile,
  actionData,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
}) {
  const errors =
    actionData && !actionData.success && actionData.step === 1
      ? (actionData.errors as Step1Errors)
      : {};
  const values =
    actionData && !actionData.success && actionData.step === 1
      ? actionData.values
      : null;

  return (
    <Form method="post" className="space-y-5">
      <input type="hidden" name="step" value="1" />
      <div className="space-y-2">
        <Label htmlFor="display_name">Nom affiché *</Label>
        <Input
          id="display_name"
          name="display_name"
          required
          defaultValue={
            (values?.display_name as string) ?? profile?.display_name ?? ""
          }
          placeholder="Ex: Jean Dupont"
        />
        <FieldError errors={errors as Record<string, string[] | undefined>} field="display_name" />
      </div>
      <div className="space-y-2">
        <Label htmlFor="headline">Accroche professionnelle *</Label>
        <Input
          id="headline"
          name="headline"
          required
          maxLength={200}
          defaultValue={(values?.headline as string) ?? profile?.headline ?? ""}
          placeholder="Ex: Expert n8n & automatisation IA"
        />
        <p className="text-xs text-muted-foreground">Max 200 caractères</p>
        <FieldError errors={errors as Record<string, string[] | undefined>} field="headline" />
      </div>
      <div className="space-y-2">
        <Label htmlFor="bio">Bio (optionnelle)</Label>
        <Textarea
          id="bio"
          name="bio"
          maxLength={2000}
          rows={4}
          defaultValue={(values?.bio as string) ?? profile?.bio ?? ""}
          placeholder="Décrivez votre parcours, vos spécialités, ce qui vous différencie..."
        />
        <p className="text-xs text-muted-foreground">Max 2000 caractères</p>
        <FieldError errors={errors as Record<string, string[] | undefined>} field="bio" />
      </div>
      <Button type="submit" className="w-full">
        Suivant →
      </Button>
    </Form>
  );
}

// ── Step 2: Expertise ────────────────────────────────────────────────────────

function Step2Form({
  profile,
  actionData,
  navigate,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
  navigate: (to: string) => void;
}) {
  const errors =
    actionData && !actionData.success && actionData.step === 2
      ? (actionData.errors as Step2Errors)
      : {};
  const values =
    actionData && !actionData.success && actionData.step === 2
      ? actionData.values
      : null;

  const existingSkills =
    (profile?.profile as Record<string, unknown> | null)?.skills as string[] ?? [];
  const existingVerticals =
    (profile?.profile as Record<string, unknown> | null)?.verticals as string[] ?? [];

  const initSelected = (values?.skills as string[]) ?? existingSkills;
  const initVerticals = (values?.verticals as string[]) ?? existingVerticals;

  const [selectedSkills, setSelectedSkills] = useState<string[]>(initSelected);
  const [selectedVerticals, setSelectedVerticals] = useState<string[]>(initVerticals);
  const [customSkill, setCustomSkill] = useState("");
  const [outcomeTags, setOutcomeTags] = useState<string[]>(
    (values?.outcome_tags as string[]) ?? profile?.outcome_tags ?? [],
  );
  const [tagInput, setTagInput] = useState("");

  function toggleSkill(skill: string) {
    setSelectedSkills((prev) =>
      prev.includes(skill)
        ? prev.filter((s) => s !== skill)
        : prev.length < 15
          ? [...prev, skill]
          : prev,
    );
  }

  function addCustomSkill() {
    const trimmed = customSkill.trim();
    if (!trimmed || selectedSkills.includes(trimmed) || selectedSkills.length >= 15) return;
    setSelectedSkills((prev) => [...prev, trimmed]);
    setCustomSkill("");
  }

  function toggleVertical(v: string) {
    setSelectedVerticals((prev) =>
      prev.includes(v) ? prev.filter((x) => x !== v) : [...prev, v],
    );
  }

  function addTag() {
    const trimmed = tagInput.trim();
    if (!trimmed || outcomeTags.includes(trimmed) || outcomeTags.length >= 10) return;
    setOutcomeTags((prev) => [...prev, trimmed]);
    setTagInput("");
  }

  return (
    <Form method="post" className="space-y-6">
      <input type="hidden" name="step" value="2" />
      {selectedSkills.map((s) => (
        <input key={s} type="hidden" name="skills" value={s} />
      ))}
      {selectedVerticals.map((v) => (
        <input key={v} type="hidden" name="verticals" value={v} />
      ))}
      {outcomeTags.map((t) => (
        <input key={t} type="hidden" name="outcome_tags" value={t} />
      ))}

      {/* Skills */}
      <div className="space-y-2">
        <Label>Compétences * ({selectedSkills.length}/15)</Label>
        <div className="flex flex-wrap gap-2 p-3 border rounded-md min-h-[60px]">
          {PREDEFINED_SKILLS.map((skill) => (
            <button
              key={skill}
              type="button"
              onClick={() => toggleSkill(skill)}
              className={[
                "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
                selectedSkills.includes(skill)
                  ? "bg-primary text-primary-foreground border-primary"
                  : "bg-background text-muted-foreground border-input hover:border-primary",
              ].join(" ")}
            >
              {skill}
            </button>
          ))}
        </div>
        {/* Custom skill input */}
        <div className="flex gap-2">
          <Input
            value={customSkill}
            onChange={(e) => setCustomSkill(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addCustomSkill();
              }
            }}
            placeholder="Ajouter une compétence..."
            className="text-sm"
          />
          <Button type="button" variant="outline" size="sm" onClick={addCustomSkill}>
            +
          </Button>
        </div>
        {selectedSkills.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1">
            {selectedSkills.map((s) => (
              <span
                key={s}
                className="inline-flex items-center gap-1 px-2 py-0.5 bg-primary/10 text-primary text-xs rounded-full"
              >
                {s}
                <button
                  type="button"
                  onClick={() =>
                    setSelectedSkills((prev) => prev.filter((x) => x !== s))
                  }
                  className="hover:text-destructive"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
        <FieldError errors={errors as Record<string, string[] | undefined>} field="skills" />
      </div>

      {/* Verticals */}
      <div className="space-y-2">
        <Label>Secteurs d'activité</Label>
        <div className="grid grid-cols-2 gap-2">
          {PREDEFINED_VERTICALS.map((v) => (
            <label key={v} className="flex items-center gap-2 cursor-pointer text-sm">
              <input
                type="checkbox"
                checked={selectedVerticals.includes(v)}
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
            defaultValue={
              (values?.rate_min as number) ?? profile?.rate_min ?? ""
            }
            placeholder="50"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="rate_max">Tarif max (€/h)</Label>
          <Input
            id="rate_max"
            name="rate_max"
            type="number"
            min={0}
            defaultValue={
              (values?.rate_max as number) ?? profile?.rate_max ?? ""
            }
            placeholder="150"
          />
        </div>
      </div>

      {/* Outcome tags */}
      <div className="space-y-2">
        <Label>Résultats types ({outcomeTags.length}/10)</Label>
        <div className="flex gap-2">
          <Input
            value={tagInput}
            onChange={(e) => setTagInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addTag();
              }
            }}
            placeholder="Ex: 25h/semaine économisées sur le traitement RFP"
            className="text-sm"
          />
          <Button type="button" variant="outline" size="sm" onClick={addTag}>
            +
          </Button>
        </div>
        {outcomeTags.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {outcomeTags.map((t) => (
              <span
                key={t}
                className="inline-flex items-center gap-1 px-2 py-0.5 bg-secondary text-secondary-foreground text-xs rounded-full"
              >
                {t}
                <button
                  type="button"
                  onClick={() => setOutcomeTags((prev) => prev.filter((x) => x !== t))}
                  className="hover:text-destructive"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}
        <FieldError errors={errors as Record<string, string[] | undefined>} field="outcome_tags" />
      </div>

      <div className="flex gap-3">
        <Button
          type="button"
          variant="outline"
          className="flex-1"
          onClick={() => navigate("/onboarding?step=1")}
        >
          ← Retour
        </Button>
        <Button type="submit" className="flex-1">
          Suivant →
        </Button>
      </div>
    </Form>
  );
}

// ── Step 3: Preferences ──────────────────────────────────────────────────────

function Step3Form({
  profile,
  actionData,
  navigate,
}: {
  profile: ExpertProfile | null;
  actionData: ActionData | undefined;
  navigate: (to: string) => void;
}) {
  const errors =
    actionData && !actionData.success && actionData.step === 3
      ? (actionData.errors as Step3Errors)
      : {};
  const values =
    actionData && !actionData.success && actionData.step === 3
      ? actionData.values
      : null;

  const existingPrefs = profile?.preferences as Record<string, unknown> | null;

  const [selectedLanguages, setSelectedLanguages] = useState<string[]>(
    (values?.languages as string[]) ?? (existingPrefs?.languages as string[]) ?? [],
  );
  const [selectedGeoZones, setSelectedGeoZones] = useState<string[]>(
    (values?.geo_zones as string[]) ?? (existingPrefs?.geo_zones as string[]) ?? [],
  );
  const [selectedIndustries, setSelectedIndustries] = useState<string[]>(
    (values?.industries as string[]) ?? (existingPrefs?.industries as string[]) ?? [],
  );
  const [selectedProjectStages, setSelectedProjectStages] = useState<string[]>(
    (values?.project_stage as string[]) ??
      (existingPrefs?.project_stage as string[]) ?? [],
  );

  const toggle = (
    list: string[],
    setList: React.Dispatch<React.SetStateAction<string[]>>,
    value: string,
  ) => {
    setList((prev) =>
      prev.includes(value) ? prev.filter((x) => x !== value) : [...prev, value],
    );
  };

  const existingBudget = existingPrefs?.budget_range as
    | { min?: number; max?: number }
    | undefined;

  return (
    <Form method="post" className="space-y-6">
      <input type="hidden" name="step" value="3" />
      {selectedLanguages.map((l) => (
        <input key={l} type="hidden" name="languages" value={l} />
      ))}
      {selectedGeoZones.map((g) => (
        <input key={g} type="hidden" name="geo_zones" value={g} />
      ))}
      {selectedIndustries.map((i) => (
        <input key={i} type="hidden" name="industries" value={i} />
      ))}
      {selectedProjectStages.map((s) => (
        <input key={s} type="hidden" name="project_stage" value={s} />
      ))}

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
                defaultChecked={
                  ((values?.career_stage as string) ??
                    (existingPrefs?.career_stage as string)) === value
                }
                required
                className="h-4 w-4"
              />
              {label}
            </label>
          ))}
        </div>
        <FieldError errors={errors as Record<string, string[] | undefined>} field="career_stage" />
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
                defaultChecked={
                  ((values?.work_mode as string) ??
                    (existingPrefs?.work_mode as string)) === value
                }
                required
                className="h-4 w-4"
              />
              {label}
            </label>
          ))}
        </div>
        <FieldError errors={errors as Record<string, string[] | undefined>} field="work_mode" />
      </div>

      {/* Availability */}
      <div className="space-y-2">
        <Label htmlFor="availability">Disponibilité *</Label>
        <select
          id="availability"
          name="availability"
          required
          defaultValue={
            (values?.availability as string) ??
            (existingPrefs?.availability as string) ??
            ""
          }
          className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        >
          <option value="">Sélectionner...</option>
          {AVAILABILITY_OPTIONS.map(({ value, label }) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
        <FieldError errors={errors as Record<string, string[] | undefined>} field="availability" />
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
            defaultValue={
              (values?.budget_min as number) ?? existingBudget?.min ?? ""
            }
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
            defaultValue={
              (values?.budget_max as number) ?? existingBudget?.max ?? ""
            }
            placeholder="50000"
          />
        </div>
      </div>

      {/* Project stage */}
      <div className="space-y-2">
        <Label>Stade du projet</Label>
        <div className="flex flex-col gap-2">
          {(
            [
              { value: "exploration", label: "Exploration (idée à valider)" },
              { value: "defined scope", label: "Scope défini (prêt à lancer)" },
              { value: "urgent execution", label: "Exécution urgente" },
            ] as const
          ).map(({ value, label }) => (
            <label key={value} className="flex items-center gap-2 cursor-pointer text-sm">
              <input
                type="checkbox"
                checked={selectedProjectStages.includes(value)}
                onChange={() =>
                  toggle(selectedProjectStages, setSelectedProjectStages, value)
                }
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

      <div className="flex gap-3">
        <Button
          type="button"
          variant="outline"
          className="flex-1"
          onClick={() => navigate("/onboarding?step=2")}
        >
          ← Retour
        </Button>
        <Button type="submit" className="flex-1">
          Suivant →
        </Button>
      </div>
    </Form>
  );
}

// ── Step 4: Google Calendar ──────────────────────────────────────────────────

function Step4Form({
  gcalStatus,
  actionData,
  navigate,
}: {
  gcalStatus: GcalStatus | null;
  actionData: ActionData | undefined;
  navigate: (to: string) => void;
}) {
  const hasError =
    actionData && !actionData.success && actionData.step === 4;
  const isConnected = gcalStatus?.connected ?? false;

  return (
    <div className="space-y-6">
      <div className="p-4 rounded-md border">
        {isConnected ? (
          <div className="space-y-1">
            <p className="text-sm font-medium text-green-600">✓ Google Calendar connecté</p>
            {gcalStatus?.email && (
              <p className="text-sm text-muted-foreground">{gcalStatus.email}</p>
            )}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            Connectez votre Google Calendar pour recevoir des rendez-vous directement dans votre
            agenda.
          </p>
        )}
      </div>

      {hasError && (
        <p className="text-sm text-destructive">
          Erreur lors de la connexion. Réessayez ou passez cette étape.
        </p>
      )}

      <div className="space-y-3">
        {!isConnected && (
          <Form method="post">
            <input type="hidden" name="step" value="4" />
            <input type="hidden" name="intent" value="connect_gcal" />
            <Button type="submit" className="w-full">
              Connecter Google Calendar
            </Button>
          </Form>
        )}

        <Form method="post">
          <input type="hidden" name="step" value="4" />
          <input
            type="hidden"
            name="intent"
            value={isConnected ? "complete" : "skip"}
          />
          <Button type="submit" variant="outline" className="w-full">
            {isConnected ? "Terminer l'onboarding →" : "Passer cette étape"}
          </Button>
        </Form>
      </div>

      <Button
        type="button"
        variant="ghost"
        className="w-full"
        onClick={() => navigate("/onboarding?step=3")}
      >
        ← Retour
      </Button>
    </div>
  );
}

// ── Main component ───────────────────────────────────────────────────────────

const STEP_TITLES = [
  "Informations de base",
  "Expertise & compétences",
  "Préférences de travail",
  "Google Calendar",
] as const;

export default function OnboardingPage() {
  const { step, profile, gcalStatus } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const navigate = useNavigate();

  // Determine active step: if action returned an error for a different step,
  // we stay on the current URL step.
  const activeStep =
    actionData && !actionData.success ? actionData.step : step;

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-xl">
        {/* Progress */}
        <div className="mb-6 space-y-3">
          <div className="flex items-center justify-between">
            <h1 className="text-xl font-semibold">Configurer votre profil</h1>
            <StepDots current={activeStep} total={4} />
          </div>
          <Progress value={(activeStep / 4) * 100} />
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{STEP_TITLES[activeStep - 1]}</CardTitle>
            {activeStep === 1 && (
              <CardDescription>
                Ces informations seront visibles par les prospects.
              </CardDescription>
            )}
            {activeStep === 2 && (
              <CardDescription>
                Définissez vos compétences pour affiner le matching.
              </CardDescription>
            )}
            {activeStep === 3 && (
              <CardDescription>
                Ces préférences guident le moteur de matching.
              </CardDescription>
            )}
            {activeStep === 4 && (
              <CardDescription>
                Connectez votre agenda pour recevoir des RDV automatiquement. Vous pouvez passer
                cette étape maintenant et le configurer depuis les paramètres.
              </CardDescription>
            )}
          </CardHeader>
          <CardContent>
            {activeStep === 1 && (
              <Step1Form profile={profile} actionData={actionData} />
            )}
            {activeStep === 2 && (
              <Step2Form profile={profile} actionData={actionData} navigate={navigate} />
            )}
            {activeStep === 3 && (
              <Step3Form profile={profile} actionData={actionData} navigate={navigate} />
            )}
            {activeStep === 4 && (
              <Step4Form gcalStatus={gcalStatus} actionData={actionData} navigate={navigate} />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
