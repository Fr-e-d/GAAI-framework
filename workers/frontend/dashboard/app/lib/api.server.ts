export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly body: unknown,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function apiFetch<T>(
  env: Env,
  token: string,
  method: "GET" | "POST" | "PATCH",
  path: string,
  params?: Record<string, string>,
  body?: unknown,
): Promise<T> {
  const url = new URL(path, env.CORE_API_URL);
  if (params) {
    Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  }

  const response = await fetch(url.toString(), {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const errorBody = await response.json().catch(() => null);
    throw new ApiError(
      response.status,
      errorBody,
      `API ${method} ${path} failed: ${response.status}`,
    );
  }

  return response.json() as Promise<T>;
}

export function apiGet<T>(
  env: Env,
  token: string,
  path: string,
  params?: Record<string, string>,
): Promise<T> {
  return apiFetch<T>(env, token, "GET", path, params);
}

export function apiPost<T>(
  env: Env,
  token: string,
  path: string,
  body: unknown,
): Promise<T> {
  return apiFetch<T>(env, token, "POST", path, undefined, body);
}

export function apiPatch<T>(
  env: Env,
  token: string,
  path: string,
  body: unknown,
): Promise<T> {
  return apiFetch<T>(env, token, "PATCH", path, undefined, body);
}
