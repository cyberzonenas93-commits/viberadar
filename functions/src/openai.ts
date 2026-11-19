/**
 * openai.ts — Server-side OpenAI proxy. Clients call the `openaiProxy` callable
 * instead of hitting the OpenAI API directly, so the API key is never shipped in
 * the app bundle. Requires Firebase Auth (`request.auth`).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import {
  OPENAI_ALLOWED_MODELS,
  OPENAI_API_KEY,
  OPENAI_DEFAULT_MODEL,
  OPENAI_MAX_COMPLETION_TOKENS,
  OPENAI_MAX_MESSAGE_CHARS,
  OPENAI_MAX_MESSAGES,
  getAllowedOpenAiModels,
  normalizeSecretValue,
} from "./lib/config";
import { appClientCallableOptions } from "./lib/appCheck";
import { requireFullCallableAccount } from "./lib/auth";
import { requireProUsageLimitsForUser } from "./lib/entitlements";
import { enforceUsageLimit } from "./lib/usage";

interface ChatMessage {
  role: string;
  content: string;
}

interface OpenAiRequest {
  messages: ChatMessage[];
  model?: string;
  maxCompletionTokens?: number;
  temperature?: number;
  /** When true, requests a JSON-object response_format (used by parseCommand). */
  jsonObject?: boolean;
}

const ENDPOINT = "https://api.openai.com/v1/chat/completions";
const ALLOWED_ROLES = new Set(["system", "user", "assistant"]);

interface SanitizedOpenAiRequest {
  messages: ChatMessage[];
  model: string;
  maxCompletionTokens: number;
  temperature: number;
  jsonObject: boolean;
}

export function sanitizeOpenAiRequest(
  data: OpenAiRequest | undefined,
  options: {
    allowedModels: string[];
    defaultModel: string;
    maxCompletionTokens: number;
    maxMessages: number;
    maxMessageChars: number;
  },
): SanitizedOpenAiRequest {
  const {
    allowedModels,
    defaultModel,
    maxCompletionTokens,
    maxMessages,
    maxMessageChars,
  } = options;
  const messages = data?.messages;

  if (!Array.isArray(messages) || messages.length === 0) {
    throw new HttpsError("invalid-argument", "messages is required");
  }
  if (messages.length > maxMessages) {
    throw new HttpsError(
      "invalid-argument",
      `messages must contain at most ${maxMessages} entries`,
    );
  }

  let totalChars = 0;
  const sanitizedMessages = messages.map((message, index) => {
    if (!ALLOWED_ROLES.has(message.role)) {
      throw new HttpsError(
        "invalid-argument",
        `messages[${index}].role is not allowed`,
      );
    }
    if (typeof message.content !== "string" || message.content.trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        `messages[${index}].content must be a non-empty string`,
      );
    }
    totalChars += message.content.length;
    if (totalChars > maxMessageChars) {
      throw new HttpsError(
        "invalid-argument",
        `messages exceed the ${maxMessageChars}-character limit`,
      );
    }
    return {
      role: message.role,
      content: message.content,
    };
  });

  const requestedModel =
    typeof data?.model === "string" && data.model.trim() !== ""
      ? data.model.trim()
      : defaultModel;
  const effectiveAllowedModels =
    allowedModels.length === 0 ? [defaultModel] : allowedModels;
  if (!effectiveAllowedModels.includes(requestedModel)) {
    throw new HttpsError("invalid-argument", "Requested model is not allowed");
  }

  const requestedMaxTokens = data?.maxCompletionTokens ?? maxCompletionTokens;
  if (
    !Number.isInteger(requestedMaxTokens) ||
    requestedMaxTokens < 1 ||
    requestedMaxTokens > maxCompletionTokens
  ) {
    throw new HttpsError(
      "invalid-argument",
      `maxCompletionTokens must be between 1 and ${maxCompletionTokens}`,
    );
  }

  const temperature = data?.temperature ?? 0.7;
  if (
    typeof temperature !== "number" ||
    Number.isNaN(temperature) ||
    temperature < 0 ||
    temperature > 2
  ) {
    throw new HttpsError(
      "invalid-argument",
      "temperature must be between 0 and 2",
    );
  }

  return {
    messages: sanitizedMessages,
    model: requestedModel,
    maxCompletionTokens: requestedMaxTokens,
    temperature,
    jsonObject: data?.jsonObject === true,
  };
}

// ── Model policy / request body ────────────────────────────────────────────

/** gpt-5 family models are reasoning models with different request rules. */
const REASONING_MODEL_RE = /^gpt-5/i;

/** Reasoning models bill thinking tokens against max_completion_tokens, so the
 * visible completion needs a guaranteed floor regardless of what an older client
 * requested. The set-builder prompt lists tracks twice (a numbered list AND the
 * ```crate JSON), so a max-size 30-track set needs ~2.1k tokens — 3500 leaves
 * margin so the crate block can't truncate (a cut-off block fails to parse). */
const MIN_REASONING_COMPLETION_TOKENS = 3500;

/** none | low | medium | high | xhigh. Lower = faster. Overridable via env. */
const DEFAULT_REASONING_EFFORT =
  process.env.OPENAI_REASONING_EFFORT?.trim() || "low";

export function isReasoningModel(model: string): boolean {
  return REASONING_MODEL_RE.test(model);
}

/**
 * Builds the OpenAI chat-completions request body. The backend owns the model:
 * any non-gpt-5 request — including already-shipped clients that still send
 * "gpt-4.1" — is redirected to the configured default, so the live AI feature
 * runs on the current model without requiring an app update. gpt-5 reasoning
 * models reject a non-default `temperature` and need a larger token budget, so
 * those params are set per-model rather than forwarded blindly.
 */
export function buildChatCompletionBody(
  sanitized: SanitizedOpenAiRequest,
  options: {
    defaultModel: string;
    maxCompletionTokensCap: number;
    reasoningEffort?: string;
  },
): Record<string, unknown> {
  const model = isReasoningModel(sanitized.model)
    ? sanitized.model
    : options.defaultModel;

  const body: Record<string, unknown> = {
    model,
    messages: sanitized.messages,
  };

  if (isReasoningModel(model)) {
    body.max_completion_tokens = Math.min(
      Math.max(sanitized.maxCompletionTokens, MIN_REASONING_COMPLETION_TOKENS),
      options.maxCompletionTokensCap,
    );
    body.reasoning_effort = options.reasoningEffort ?? DEFAULT_REASONING_EFFORT;
  } else {
    body.max_completion_tokens = sanitized.maxCompletionTokens;
    body.temperature = sanitized.temperature;
  }

  if (sanitized.jsonObject) {
    body.response_format = { type: "json_object" };
  }

  return body;
}

export const openaiProxy = onCall(
  {
    region: "us-central1",
    secrets: [OPENAI_API_KEY],
    timeoutSeconds: 120,
    ...appClientCallableOptions,
  },
  async (
    request: CallableRequest<OpenAiRequest>,
  ): Promise<{ content: string; model: string }> => {
    const auth = requireFullCallableAccount(
      request.auth,
      "A full account is required to use AI requests.",
    );

    const apiKey = normalizeSecretValue(OPENAI_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError("internal", "OpenAI key is not configured");
    }

    const sanitized = sanitizeOpenAiRequest(request.data, {
      allowedModels:
        getAllowedOpenAiModels().length > 0
          ? getAllowedOpenAiModels()
          : OPENAI_ALLOWED_MODELS.value().split(","),
      defaultModel: OPENAI_DEFAULT_MODEL.value(),
      maxCompletionTokens: OPENAI_MAX_COMPLETION_TOKENS.value(),
      maxMessages: OPENAI_MAX_MESSAGES.value(),
      maxMessageChars: OPENAI_MAX_MESSAGE_CHARS.value(),
    });

    const { limits } = await requireProUsageLimitsForUser(
      auth.uid,
      "VibeRadar Pro is required to use AI set building.",
    );
    await enforceUsageLimit({
      uid: auth.uid,
      key: "ai_requests",
      limit: limits.aiMonthlyLimit,
      window: "monthly",
    });

    const body = buildChatCompletionBody(sanitized, {
      defaultModel: OPENAI_DEFAULT_MODEL.value(),
      maxCompletionTokensCap: OPENAI_MAX_COMPLETION_TOKENS.value(),
    });

    const response = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new HttpsError(
        "internal",
        `OpenAI error ${response.status}: ${text.slice(0, 300)}`,
      );
    }

    const json = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
      model?: string;
    };
    return {
      content: json.choices?.[0]?.message?.content ?? "",
      model: json.model ?? (body.model as string),
    };
  },
);
