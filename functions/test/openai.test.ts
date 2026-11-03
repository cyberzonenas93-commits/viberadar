import assert from "node:assert/strict";
import {
  buildChatCompletionBody,
  isReasoningModel,
  sanitizeOpenAiRequest,
} from "../src/openai";

const options = {
  allowedModels: ["gpt-4.1", "gpt-4o-mini"],
  defaultModel: "gpt-4.1",
  maxCompletionTokens: 1000,
  maxMessages: 3,
  maxMessageChars: 100,
};

const sanitized = sanitizeOpenAiRequest(
  {
    messages: [{ role: "user", content: "build a set" }],
    model: "gpt-4o-mini",
    maxCompletionTokens: 500,
    temperature: 0.3,
  },
  options,
);
assert.equal(sanitized.model, "gpt-4o-mini");
assert.equal(sanitized.maxCompletionTokens, 500);

assert.throws(
  () =>
    sanitizeOpenAiRequest(
      {
        messages: [{ role: "tool", content: "nope" }],
      },
      options,
    ),
  /role is not allowed/,
);

assert.throws(
  () =>
    sanitizeOpenAiRequest(
      {
        messages: [{ role: "user", content: "x".repeat(101) }],
      },
      options,
    ),
  /character limit/,
);

assert.throws(
  () =>
    sanitizeOpenAiRequest(
      {
        messages: [{ role: "user", content: "hello" }],
        model: "gpt-unknown",
      },
      options,
    ),
  /not allowed/,
);

assert.throws(
  () =>
    sanitizeOpenAiRequest(
      {
        messages: [{ role: "user", content: "hello" }],
        maxCompletionTokens: 1001,
      },
      options,
    ),
  /maxCompletionTokens/,
);

// ── Model policy: buildChatCompletionBody ──────────────────────────────────

assert.equal(isReasoningModel("gpt-5.5"), true);
assert.equal(isReasoningModel("gpt-5"), true);
assert.equal(isReasoningModel("gpt-4.1"), false);
assert.equal(isReasoningModel("gpt-4o-mini"), false);

const sanitizedLegacy = {
  messages: [{ role: "user", content: "build a set" }],
  model: "gpt-4.1",
  maxCompletionTokens: 1500,
  temperature: 0.7,
  jsonObject: false,
};

// A shipped client asking for gpt-4.1 is redirected to the gpt-5.5 default,
// temperature is dropped (gpt-5 rejects it), reasoning_effort is set, and the
// token budget is floored to leave room for visible output.
const reasoningBody = buildChatCompletionBody(sanitizedLegacy, {
  defaultModel: "gpt-5.5",
  maxCompletionTokensCap: 4000,
});
assert.equal(reasoningBody.model, "gpt-5.5");
assert.equal("temperature" in reasoningBody, false);
assert.equal(reasoningBody.reasoning_effort, "low");
assert.equal(reasoningBody.max_completion_tokens, 3500); // floored up from 1500

// The 400-token JSON-parse path is also floored so reasoning can't starve it.
const jsonBody = buildChatCompletionBody(
  { ...sanitizedLegacy, maxCompletionTokens: 400, jsonObject: true },
  { defaultModel: "gpt-5.5", maxCompletionTokensCap: 4000 },
);
assert.equal(jsonBody.max_completion_tokens, 3500);
assert.deepEqual(jsonBody.response_format, { type: "json_object" });

// An explicit gpt-5.x model is preserved (not overridden by the default).
const explicit5 = buildChatCompletionBody(
  { ...sanitizedLegacy, model: "gpt-5.5-pro" },
  { defaultModel: "gpt-5.5", maxCompletionTokensCap: 4000 },
);
assert.equal(explicit5.model, "gpt-5.5-pro");
assert.equal(explicit5.reasoning_effort, "low");

// Non-reasoning default keeps the classic temperature path.
const classicBody = buildChatCompletionBody(
  { ...sanitizedLegacy, model: "gpt-4o-mini" },
  { defaultModel: "gpt-4.1", maxCompletionTokensCap: 1500 },
);
assert.equal(classicBody.model, "gpt-4.1");
assert.equal(classicBody.temperature, 0.7);
assert.equal(classicBody.max_completion_tokens, 1500);
assert.equal("reasoning_effort" in classicBody, false);

console.log("openai.test.ts: all assertions passed");
