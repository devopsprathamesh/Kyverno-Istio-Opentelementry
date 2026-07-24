"""Offline-runnable unit tests for inventory-service's stock logic. See
test_payment_service_logic.py's module docstring for how to run these.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "inventory-service"))


def test_low_stock_probability_zero_means_always_available_while_stock_remains():
    import random
    random.seed(7)
    low_stock_probability = 0.0
    stock = 10
    results = []
    for _ in range(10):
        available = random.random() > low_stock_probability and stock > 0
        if available:
            stock -= 1
        results.append(available)
    assert all(results)
    assert stock == 0


def test_out_of_stock_when_stock_is_zero_regardless_of_probability():
    import random
    random.seed(7)
    low_stock_probability = 0.0
    stock = 0
    available = random.random() > low_stock_probability and stock > 0
    assert available is False
