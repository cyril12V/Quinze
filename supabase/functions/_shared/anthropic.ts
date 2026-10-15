// Client minimal de l'API Messages d'Anthropic via fetch (aucun SDK, aucun global Deno).
//   POST https://api.anthropic.com/v1/messages
//   en-têtes : x-api-key, anthropic-version: 2023-06-01
// Délai ~20 s par tentative ; UNE nouvelle tentative sur 429 / 5xx (dont 529) ou erreur réseau,
// jamais sur délai dépassé. Le corps des erreurs du fournisseur n'est ni lu ni journalisé.

export const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
export const ANTHROPIC_VERSION = "2023-06-01";
export const DEFAULT_MODEL = "claude-haiku-5-5";
export const DEFAULT_TIMEOUT_MS = 20_000;

export interface ModelCall {
  apiKey: string | undefined;
  model: string;
  system: string;
  user: string;
  maxTokens: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export type ModelResult =
  | {
      ok: true;
      text: string;
      model: string;
      inputTokens: number | null;
      outputTokens: number | null;
      stopReason: string | null;
      latencyMs: number;
      attempts: number;
    }
  | {
      ok: false;
      kind: "no_key" | "timeout" | "network" | "http" | "empty" | "invalid_response";
      status?: number;
      latencyMs: number;
      attempts: number;
    };

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function retryDelayMs(res: Response): number {
  const h = res.headers.get("retry-after");
  const s = h ? Number.parseFloat(h) : NaN;
  if (Number.isFinite(s) && s >= 0) return Math.min(2000, Math.round(s * 1000));
  return 400;
}

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

export async function callAnthropic(c: ModelCall): Promise<ModelResult> {
  const started = Date.now();
  const elapsed = () => Date.now() - started;
  if (!c.apiKey) return { ok: false, kind: "no_key", latencyMs: 0, attempts: 0 };

  const doFetch = c.fetchImpl ?? fetch;
  const sleep = c.sleep ?? defaultSleep;
  const timeoutMs = c.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const body = JSON.stringify({
    model: c.model,
    max_tokens: c.maxTokens,
    system: c.system,
    messages: [{ role: "user", content: c.user }],
  });

  let lastFailure: ModelResult = { ok: false, kind: "network", latencyMs: 0, attempts: 0 };
  for (let attempt = 1; attempt <= 2; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let res: Response;
    try {
      res = await doFetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": c.apiKey,
          "anthropic-version": ANTHROPIC_VERSION,
        },
        body,
        signal: controller.signal,
      });
    } catch (e) {
      clearTimeout(timer);
      const aborted = controller.signal.aborted || (e instanceof Error && e.name === "AbortError");
      if (aborted) return { ok: false, kind: "timeout", latencyMs: elapsed(), attempts: attempt };
      lastFailure = { ok: false, kind: "network", latencyMs: elapsed(), attempts: attempt };
      if (attempt < 2) {
        await sleep(400);
        continue;
      }
      return lastFailure;
    }
    clearTimeout(timer);

    if (res.ok) {
      let data: unknown;
      try {
        data = await res.json();
      } catch {
        return { ok: false, kind: "invalid_response", status: res.status, latencyMs: elapsed(), attempts: attempt };
      }
      const d = data as { content?: unknown; model?: unknown; usage?: { input_tokens?: unknown; output_tokens?: unknown }; stop_reason?: unknown };
      const blocks = Array.isArray(d.content) ? d.content : [];
      const text = blocks
        .map((b) => (b && typeof b === "object" && (b as { type?: unknown }).type === "text" ? String((b as { text?: unknown }).text ?? "") : ""))
        .join("")
        .trim();
      if (text === "") return { ok: false, kind: "empty", status: res.status, latencyMs: elapsed(), attempts: attempt };
      return {
        ok: true,
        text,
        model: typeof d.model === "string" ? d.model : c.model,
        inputTokens: num(d.usage?.input_tokens),
        outputTokens: num(d.usage?.output_tokens),
        stopReason: typeof d.stop_reason === "string" ? d.stop_reason : null,
        latencyMs: elapsed(),
        attempts: attempt,
      };
    }

    const retryable = res.status === 429 || res.status >= 500;
    lastFailure = { ok: false, kind: "http", status: res.status, latencyMs: elapsed(), attempts: attempt };
    if (retryable && attempt < 2) {
      const wait = retryDelayMs(res);
      try {
        await res.body?.cancel();
      } catch {
        // ignoré
      }
      await sleep(wait);
      continue;
    }
    return lastFailure;
  }
  return lastFailure;
}
