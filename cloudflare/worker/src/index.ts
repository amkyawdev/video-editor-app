/**
 * Translation proxy for Movie Recap Studio.
 * Validates input, applies CORS and a small per-isolate rate limit, and calls
 * an OpenAI-compatible translation provider. Provider credentials come from
 * Worker secrets and are never returned to the client.
 */
export interface Env {
  TRANSLATION_PROVIDER_URL: string;
  TRANSLATION_PROVIDER_KEY: string;
  ALLOWED_ORIGINS?: string;
}

type TranslateRequest = {
  texts?: unknown;
  target?: unknown;
  source?: unknown;
};

const WINDOW_MS = 60_000;
const MAX_REQUESTS = 30;
const MAX_TEXTS = 40;
const MAX_CHARS = 12_000;
const buckets = new Map<string, { count: number; reset: number }>();

function cors(origin: string | null, env: Env): Record<string, string> {
  const allowed = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const permit =
    !origin || allowed.length === 0 || allowed.includes(origin) ? (origin ?? '*') : '';
  return {
    'Access-Control-Allow-Origin': permit,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json',
    Vary: 'Origin',
  };
}

function limited(key: string): boolean {
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || bucket.reset < now) {
    buckets.set(key, { count: 1, reset: now + WINDOW_MS });
    return false;
  }
  bucket.count += 1;
  return bucket.count > MAX_REQUESTS;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get('Origin');
    const headers = cors(origin, env);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') {
      return Response.json({ error: 'method_not_allowed' }, { status: 405, headers });
    }
    if (!headers['Access-Control-Allow-Origin']) {
      return Response.json({ error: 'origin_not_allowed' }, { status: 403, headers });
    }

    const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
    if (limited(ip)) {
      return Response.json({ error: 'rate_limited' }, { status: 429, headers });
    }

    let body: TranslateRequest;
    try {
      body = (await request.json()) as TranslateRequest;
    } catch {
      return Response.json({ error: 'invalid_json' }, { status: 400, headers });
    }
    const texts = body.texts;
    const target = typeof body.target === 'string' ? body.target.slice(0, 16) : '';
    const source = typeof body.source === 'string' ? body.source.slice(0, 16) : '';
    if (!Array.isArray(texts) || texts.length === 0 || texts.length > MAX_TEXTS) {
      return Response.json({ error: 'invalid_texts' }, { status: 400, headers });
    }
    const clean = texts.map((value) => (typeof value === 'string' ? value : ''));
    if (clean.some((value) => value.length > 4000)) {
      return Response.json({ error: 'text_too_long' }, { status: 413, headers });
    }
    if (clean.join('').length > MAX_CHARS) {
      return Response.json({ error: 'batch_too_large' }, { status: 413, headers });
    }
    if (!target) return Response.json({ error: 'missing_target' }, { status: 400, headers });

    const prompt = [
      `Translate each numbered line into ${target}${source ? ` from ${source}` : ''}.`,
      'Keep one output line per input line, numbered the same way.',
      'Do not add explanations or merge lines.',
      ...clean.map((text, index) => `${index + 1}. ${text}`),
    ].join('\n');

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 45_000);
    try {
      const upstream = await fetch(env.TRANSLATION_PROVIDER_URL, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${env.TRANSLATION_PROVIDER_KEY}`,
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          temperature: 0.2,
          messages: [
            { role: 'system', content: 'You translate subtitles faithfully.' },
            { role: 'user', content: prompt },
          ],
        }),
      });
      if (!upstream.ok) {
        return Response.json({ error: 'provider_error', status: upstream.status }, { status: 502, headers });
      }
      const data = (await upstream.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const raw = data.choices?.[0]?.message?.content ?? '';
      const parsed = raw
        .split('\n')
        .map((line) => line.match(/^\s*\d+[.)]\s*(.+)$/)?.[1]?.trim() ?? '')
        .filter(Boolean);
      if (parsed.length !== clean.length) {
        return Response.json({ error: 'bad_provider_output' }, { status: 502, headers });
      }
      return Response.json({ translations: parsed }, { headers });
    } catch (error) {
      const aborted = error instanceof Error && error.name === 'AbortError';
      return Response.json(
        { error: aborted ? 'provider_timeout' : 'upstream_unreachable' },
        { status: 504, headers },
      );
    } finally {
      clearTimeout(timeout);
    }
  },
};
