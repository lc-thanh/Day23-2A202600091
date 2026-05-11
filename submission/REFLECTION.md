# Day 23 Lab Reflection

**Student:** Le Cong Thanh
**ID:** 2A202600091
**Submission date:** 2026-05-11
**Lab repo URL:** [original](https://github.com/VinUni-AI20k/Day23-Track2-Observability-Lab.git) | [forked](https://github.com/lc-thanh/Day23-2A202600091.git)

---

## 1. Hardware + setup output

Output of `python3 00-setup/verify-docker.py`:

```text
Docker:        OK  (29.0.1)
Compose v2:    OK  (2.40.3-desktop.1)
RAM available: 31.13 GB (OK)
Ports free:    BOUND: [8000, 9090, 9093, 3000, 3100, 16686, 4317, 4318, 8888]
Report written: /home/thanh_wsl/ai/Day23-2A202600091/00-setup/setup-report.json
```

The ports were already bound because the Day 23 Compose stack was running when I re-ran the check. The committed setup report still confirms Docker, Compose v2, and RAM are OK.

---

## 2. Track 02 — Dashboards & Alerts

### 6 essential panels (screenshot)

Screenshot: `submission/screenshots/dashboard-overview.png`

The overview dashboard shows the core AI service panels after load: request rate, latency, errors, simulated resource/GPU usage, tokens, and cost-oriented telemetry. The `/metrics` endpoint exposed the required series, including `inference_requests_total`, `inference_latency_seconds_bucket`, `inference_active_gauge`, `inference_tokens_total`, and `inference_quality_score`.

### Burn-rate panel

Screenshot: `submission/screenshots/slo-burn-rate.png`

The SLO burn-rate dashboard was used to connect the alerting rules to error-budget behavior instead of looking only at raw request failures.

### Cost and tokens panel

Screenshot: `submission/screenshots/cost-and-tokens.png`

The cost-and-tokens dashboard showed token throughput and the cost estimate from the mock LLM workload after traffic was generated.

### Active gauge evidence

Screenshots: `submission/screenshots/active-gauge.png` and `submission/screenshots/active-gauge-detail.png`

The active request gauge rose during load and returned to zero after the load finished. A later metrics check showed:

```text
inference_active_gauge 0.0
inference_tokens_total{direction="input",model="llama3-mock"} 32824.0
inference_tokens_total{direction="output",model="llama3-mock"} 130802.0
inference_quality_score{model="llama3-mock"} 0.667
```

### Alert fire + resolve

| When | What | Evidence |
|---|---|---|
| T0 | killed `day23-app` through `make alert` | screenshot `submission/screenshots/alertmanager-firing.png` |
| T0+90s | `ServiceDown` fired | screenshot `submission/screenshots/slack-fire-resolve.png` |
| T1 | app restored by the alert script | screenshot `submission/screenshots/alertmanager-firing.png` |
| T1+60s | alert resolved | screenshot `submission/screenshots/slack-fire-resolve.png` |

### One thing surprised me about Prometheus / Grafana

The surprising part was how much the dashboard usefulness depended on label choices and query windows, not only on whether the metrics existed. A counter like `inference_requests_total` is easy to expose, but it only becomes useful when Grafana turns it into rates and percentiles that match the operator question: is the service healthy right now, and is the error budget burning too fast?

---

## 3. Track 03 — Tracing & Logs

### One trace screenshot from Jaeger

Screenshot: `submission/screenshots/jaeger-trace.png`

The Jaeger trace shows a `POST /predict` request and the expected child spans for the mock inference pipeline: `embed-text`, `vector-search`, and `generate-tokens`.

### Span attributes screenshot

Screenshot: `submission/screenshots/jaeger-span-attrs.png`

The span attributes panel shows model/request metadata on the inference trace, which makes the trace useful for AI debugging instead of just generic HTTP timing.

### Log line correlated to trace

Structured JSON log line with `trace_id`:

```json
{"model": "llama3-mock", "input_tokens": 8, "output_tokens": 8, "quality": 0.855, "duration_seconds": 0.1644, "trace_id": "c2cb1b69cfc184f3f0c6c42689df2b03", "event": "prediction served", "level": "info", "timestamp": "2026-05-11T12:29:55.102672Z"}
```

Trace ID:

```text
c2cb1b69cfc184f3f0c6c42689df2b03
```

This is the key join field between logs and traces: the log explains what the model request did, while Jaeger shows where time was spent.

### Tail-sampling math

The collector policy keeps 100% of error traces, 100% of slow traces, and 1% of healthy traces. For a service producing `N` traces/sec with 1% errors, 1% slow non-error traces, and 98% healthy traces:

```text
sampled = N × (P(error) × 1.0 + P(slow and not error) × 1.0 + P(healthy) × 0.01)
sampled = N × (0.01 × 1.0 + 0.01 × 1.0 + 0.98 × 0.01)
sampled = N × (0.01 + 0.01 + 0.0098)
sampled = N × 0.0298
```

So the collector retains about 2.98%, or roughly 3%, of traces in that traffic mix. The important operational result is that forced-error traces are retained while most healthy traces are dropped, which preserves high-signal debugging data without storing every normal request.

---

## 4. Track 04 — Drift Detection

### PSI scores

`04-drift-detection/reports/drift-summary.json`:

```json
{
  "prompt_length": {
    "psi": 3.461,
    "kl": 1.7982,
    "ks_stat": 0.702,
    "ks_pvalue": 0.0,
    "drift": "yes"
  },
  "embedding_norm": {
    "psi": 0.0187,
    "kl": 0.0324,
    "ks_stat": 0.052,
    "ks_pvalue": 0.133853,
    "drift": "no"
  },
  "response_length": {
    "psi": 0.0162,
    "kl": 0.0178,
    "ks_stat": 0.056,
    "ks_pvalue": 0.086899,
    "drift": "no"
  },
  "response_quality": {
    "psi": 8.8486,
    "kl": 13.5011,
    "ks_stat": 0.941,
    "ks_pvalue": 0.0,
    "drift": "yes"
  }
}
```

Screenshot: `submission/screenshots/drift-report.png`

The drift report shows that `prompt_length` and `response_quality` drifted, while `embedding_norm` and `response_length` stayed close to the baseline distribution.

### Which test fits which feature?

For `prompt_length`, I would use PSI in production because prompt length is a stable numeric feature that is easy to bucket and monitor over time. The observed PSI of 3.461 is far above the common 0.2 drift threshold, so this is a clear distribution shift.

For `embedding_norm`, I would use KS for the single scalar norm and MMD if I were comparing the full embedding vectors. KS is appropriate for the one-dimensional norm because it detects changes in continuous distributions without assuming a parametric shape, while MMD is better for high-dimensional embedding drift.

For `response_length`, I would use KS or PSI. KS is useful because response length is continuous/count-like and can shift in shape, while PSI is useful for dashboarding binned production monitoring. In this run, both PSI and KS stayed small, so response length did not show meaningful drift.

For `response_quality`, I would use KS and PSI together. KS tests whether the score distribution changed, while PSI gives an interpretable monitoring score for production dashboards. The PSI of 8.8486 and KS statistic of 0.941 indicate a major quality distribution shift.

---

## 5. Track 05 — Cross-Day Integration

### Which prior-day metric was hardest to expose? Why?

This section was not completed because the cross-day integration screenshot/source was skipped. Based on the integration options, the hardest prior-day metric to expose would likely be a real pipeline or lakehouse metric, such as Airflow DAG duration or Spark/Delta metrics, because those require another service stack to be running with compatible Prometheus endpoints.

The easier path for this lab would be stub metrics, because the cross-day dashboard is designed to fail soft and can still render panels with either stub data or `No Data`. For a production setup, I would prioritize one real prior-day source first, then add the rest once the scrape targets and labels are stable.

---

## 6. The single change that mattered most

The single change that mattered most was connecting the AI-specific metrics, especially tokens and quality, to the same operational view as RED metrics. Basic HTTP observability can tell me that `/predict` is fast and returning 200s, but it cannot tell me whether the model is getting more expensive or whether output quality is drifting. Adding `inference_tokens_total` and `inference_quality_score` made the dashboard useful for an AI service rather than just a generic web API.

This connects directly to the fourth pillar of AI observability from the deck: model behavior must be monitored alongside metrics, logs, and traces. The cost-and-tokens dashboard shows whether traffic is becoming expensive, the quality gauge shows whether the mock model output is degrading, and the drift report shows whether production-like data has shifted from baseline. Together with trace/log correlation by `trace_id`, the stack moves from "the service is up" to "the service is operating correctly, affordably, and with explainable failures."
