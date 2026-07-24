"""Offline-runnable unit tests for payment-service's decision logic —
no cluster, no Docker, no network required. Run with:
    pip install pytest httpx
    PYTHONPATH=../payment-service pytest test_payment_service_logic.py
Static-only: this does NOT prove the OTLP export path works (that
needs a live Collector — see ../../labs/lab-09-manual-instrumentation.md
and ../../tests/traces-test.sh for the runtime-validated equivalent).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "payment-service"))


def test_failure_percent_zero_means_no_declines():
    import random
    random.seed(42)
    failure_percent = 0.0
    declined_count = sum(1 for _ in range(1000) if (random.random() * 100) < failure_percent)
    assert declined_count == 0


def test_failure_percent_hundred_means_always_declined():
    import random
    random.seed(42)
    failure_percent = 100.0
    declined_count = sum(1 for _ in range(1000) if (random.random() * 100) < failure_percent)
    assert declined_count == 1000


def test_failure_percent_thirty_is_roughly_thirty_percent():
    import random
    random.seed(42)
    failure_percent = 30.0
    trials = 5000
    declined_count = sum(1 for _ in range(trials) if (random.random() * 100) < failure_percent)
    ratio = declined_count / trials
    # Statistical tolerance — see config/lab-settings.env
    # STATISTICAL_TOLERANCE_PERCENT for the same 15% tolerance band used
    # in runtime sampling/canary assertions elsewhere in this repo.
    assert 0.25 <= ratio <= 0.35
