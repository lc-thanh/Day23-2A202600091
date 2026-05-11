# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This repository is a Day 23 Track 2 observability lab for an AI inference service. It runs a 7-service Docker Compose stack: a FastAPI mock LLM app, Prometheus, Grafana, Alertmanager, Loki, Jaeger, and an OpenTelemetry Collector. The grader expects `make verify` to pass.

The main learning tracks are organized by directory:

- `00-setup/`: Docker/Python pre-flight checks and setup report generation.
- `01-instrument-fastapi/`: FastAPI service that emits Prometheus metrics, OTLP traces, and structured logs.
- `02-prometheus-grafana/`: Prometheus scrape/rule config, Alertmanager Slack routing, Grafana provisioning, dashboards, and Locust load test.
- `03-tracing-and-logs/`: OTel Collector, Jaeger, Loki, and tail-sampling configuration.
- `04-drift-detection/`: Evidently-based drift detection script and generated report artifacts.
- `05-integration/`: cross-day observability dashboard and monitor/stub scripts for prior lab days.
- `scripts/`: rubric verification, alert trigger, and dashboard lint helpers.

## Common commands

Run commands from the repository root unless noted otherwise.

```bash
make setup              # one-time setup: create .env, pull images, run Docker checks
make up                 # start the full Compose stack
make smoke              # health-check all 7 services
make logs               # tail Compose logs from all services
make down               # stop stack, preserving volumes
make restart            # stop and start the stack
make clean              # stop stack and remove volumes (destructive)
```

Validation and lab workflows:

```bash
make load               # run 60s headless Locust load against the FastAPI app
make alert              # trigger alert flow by stopping/restoring the app
make trace              # send one traced /predict request and print trace_id
make drift              # run 04-drift-detection/scripts/drift_detect.py
make demo               # run load, alert, trace, and drift in sequence
make verify             # rubric gate; exits 0 only if all checkpoints pass
make lint-dashboards    # validate Grafana dashboard JSON structure
```

Useful direct commands:

```bash
python3 00-setup/verify-docker.py
python3 scripts/verify.py
python3 scripts/lint-dashboards.py 02-prometheus-grafana/grafana/dashboards/*.json
cd 04-drift-detection && python3 scripts/drift_detect.py
cd 02-prometheus-grafana/load-test && locust -f locustfile.py --headless -u 10 -r 2 -t 60s --host http://localhost:8000
```

Run the FastAPI app standalone without the full stack:

```bash
cd 01-instrument-fastapi/app
pip install -r ../../requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

There is no dedicated unit test framework configured in this repo. Use the rubric and targeted validation commands above as the test suite.

## Service ports and endpoints

All Compose ports are bound to localhost.

- FastAPI app: `http://localhost:8000`, with `GET /healthz`, `POST /predict`, and `GET /metrics`.
- Prometheus: `http://localhost:9090`.
- Alertmanager: `http://localhost:9093`.
- Grafana: `http://localhost:3000` (`admin/admin` by default; password can be overridden with `GRAFANA_ADMIN_PW`).
- Loki: `http://localhost:3100`.
- Jaeger UI: `http://localhost:16686`.
- OTel Collector: OTLP gRPC `4317`, OTLP HTTP `4318`, self-metrics `8888`.

## Architecture notes

The FastAPI service in `01-instrument-fastapi/app/` is the telemetry source. `main.py` defines the HTTP API, `inference.py` simulates inference behavior, and `instrumentation.py` defines metrics, logging, and OTel setup. Prometheus scrapes the app's `/metrics` endpoint and collector self-metrics using config in `02-prometheus-grafana/prometheus/prometheus.yml`.

Grafana is provisioned as code from `02-prometheus-grafana/grafana/provisioning/` and loads dashboards from `02-prometheus-grafana/grafana/dashboards/`. Dashboard JSON should remain valid and provisionable; run `make lint-dashboards` after edits.

Alerting is split between Prometheus rule files in `02-prometheus-grafana/prometheus/rules/` and Alertmanager routing in `02-prometheus-grafana/alertmanager/`. Slack notifications use `SLACK_WEBHOOK_URL` from `.env`; `.env.example` is the template.

Tracing flows from the app to the OTel Collector via OTLP/gRPC, then to Jaeger. The collector config in `03-tracing-and-logs/otel-collector/otel-config.yaml` owns tail-sampling policy. Keep error and slow-trace retention behavior aligned with `03-tracing-and-logs/README.md`.

Loki is configured under `03-tracing-and-logs/loki/`. Grafana datasource provisioning is expected to link logs and traces by `trace_id`.

Drift detection is host-side Python, not a Compose service. `make drift` runs `04-drift-detection/scripts/drift_detect.py`, producing `04-drift-detection/reports/drift-report.html` and `drift-summary.json`. The root `requirements.txt` pins the Python dependencies used by the app, Locust, verification scripts, and drift detection.

## Submission and grading expectations

`make verify` checks for setup output, running service health, app metrics, Grafana dashboards, tracing/logging services, a drift summary with at least one drifted feature, and a non-trivial `submission/REFLECTION.md`. The repository README states that graders run `make verify` and expect exit code 0.

Generated drift artifacts under `04-drift-detection/reports/` and data under `04-drift-detection/data/` may be part of lab output. Be deliberate before deleting or regenerating them.
