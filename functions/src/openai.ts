/**
 * openai.ts — Server-side OpenAI proxy. Clients call the `openaiProxy` callable
 * instead of hitting the OpenAI API directly, so the API key is never shipped in
 * the app bundle. Requires Firebase Auth (`request.auth`).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { OPENAI_API_KEY, normalizeSecretValue } from "./lib/config";

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

export const openaiProxy = onCall(
  {
    region: "us-central1",
    secrets: [OPENAI_API_KEY],
    timeoutSeconds: 120,
  },
  async (
    request: CallableRequest<OpenAiRequest>,
  ): Promise<{ content: string }> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const apiKey = normalizeSecretValue(OPENAI_API_KEY.value());
    if (!apiKey) {
      throw new HttpsError("internal", "OpenAI key is not configured");
    }

    const {
      messages,
      model = "gpt-5.4",
      maxCompletionTokens = 1500,
      temperature = 0.7,
      jsonObject = false,
    } = request.data ?? {};

    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "messages is required");
    }

    const body: Record<string, unknown> = {
      model,
      messages,
      max_completion_tokens: maxCompletionTokens,
      temperature,
    };
    if (jsonObject) {
      body.response_format = { type: "json_object" };
    }

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
    };
    return { content: json.choices?.[0]?.message?.content ?? "" };
  },
);
