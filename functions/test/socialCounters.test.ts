import assert from "node:assert/strict";
import { diffStringArrays } from "../src/socialCounters";

type TestCase = {
  name: string;
  before: string[];
  after: string[];
  added: string[];
  removed: string[];
};

const cases: TestCase[] = [
  {
    name: "detects one added like",
    before: ["upload-a"],
    after: ["upload-a", "upload-b"],
    added: ["upload-b"],
    removed: [],
  },
  {
    name: "detects one removed like",
    before: ["upload-a", "upload-b"],
    after: ["upload-b"],
    added: [],
    removed: ["upload-a"],
  },
  {
    name: "deduplicates repeated ids before diffing",
    before: ["upload-a", "upload-a"],
    after: ["upload-a", "upload-b", "upload-b"],
    added: ["upload-b"],
    removed: [],
  },
];

for (const testCase of cases) {
  const result = diffStringArrays(testCase.before, testCase.after);
  assert.deepEqual(result.added, testCase.added, testCase.name);
  assert.deepEqual(result.removed, testCase.removed, testCase.name);
}

console.log(`socialCounters.test.ts: ${cases.length} assertions passed`);
