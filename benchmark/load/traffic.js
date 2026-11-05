// The load test's traffic (.shipkit/specs/deploy-shape-benchmark/, REQ-9 and
// REQ-12). k6 starts each request on schedule, whatever the app's response
// times, so a slower app gets the same arrival rate rather than fewer requests.
// compose.yml's k6 service runs it:
//
//   docker compose -f benchmark/load/compose.yml run --rm \
//     --env RATE=50 --env DURATION=120s --env MIX=healthy k6 run /scripts/traffic.js
import http from "k6/http";
import exec from "k6/execution";

const BASE_URL = __ENV.BASE_URL || "http://app";
const RATE = Number(__ENV.RATE);
const MIX = __ENV.MIX || "healthy";

// One failing request in this many, per mix: none, one in a hundred, or all.
const FAILING_ONE_IN = { healthy: 0, failing: 100, storm: 1 }[MIX];

if (!(RATE > 0)) throw new Error(`RATE must be a number of requests a second, not ${__ENV.RATE}`);
if (FAILING_ONE_IN === undefined) throw new Error(`MIX must be healthy, failing or storm, not ${MIX}`);

export const options = {
  scenarios: {
    traffic: {
      executor: "constant-arrival-rate",
      rate: RATE,
      timeUnit: "1s",
      duration: __ENV.DURATION || "120s",
      // Enough for each request to take a second, and up to four before k6
      // has to skip one, which it counts in dropped_iterations.
      preAllocatedVUs: Math.ceil(RATE),
      maxVUs: Math.ceil(RATE) * 4,
    },
  },
  // Nothing reads the bodies, so k6 needn't keep them.
  discardResponseBodies: true,
  summaryTrendStats: ["med", "p(95)", "p(99)", "max"],
  // Empty thresholds make k6 report each kind of request on its own.
  thresholds: {
    "http_reqs{kind:healthy}": [],
    "http_reqs{kind:failing}": [],
  },
};

const healthy = { tags: { kind: "healthy" }, responseCallback: http.expectedStatuses(200) };
const failing = { tags: { kind: "failing" }, responseCallback: http.expectedStatuses(500) };

export default function () {
  const fails = FAILING_ONE_IN > 0 && exec.scenario.iterationInTest % FAILING_ONE_IN === 0;

  if (fails) {
    http.get(`${BASE_URL}/orders/42/charge`, failing);
  } else {
    http.get(`${BASE_URL}/orders/42`, healthy);
  }
}

// The run's summary, as JSON on stdout, for whatever started k6 to read.
export function handleSummary(data) {
  return { stdout: JSON.stringify(data) };
}
