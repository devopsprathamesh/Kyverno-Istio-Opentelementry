#!/usr/bin/env python3
"""Bounded HTTP load generator for the demo app's frontend. Not
instrumented itself (it is test tooling, not part of the traced
application) — the traces/metrics/logs it produces come entirely from
the frontend/order-service/inventory-service/payment-service chain it
calls. Used by scripts/generate-load.sh and
combined-observability-lab/scenarios/.
"""
import argparse
import asyncio
import sys
import time
from collections import Counter

import httpx


async def worker(client: httpx.AsyncClient, url: str, results: Counter, deadline: float, sem: asyncio.Semaphore):
    while time.time() < deadline:
        async with sem:
            try:
                resp = await client.get(url, timeout=10)
                results[str(resp.status_code)] += 1
            except httpx.HTTPError as exc:
                results[f"error:{type(exc).__name__}"] += 1


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="Base URL of the frontend service")
    parser.add_argument("--requests", type=int, default=200)
    parser.add_argument("--concurrency", type=int, default=10)
    parser.add_argument("--duration", type=int, default=60, help="Max seconds to run, whichever limit hits first")
    args = parser.parse_args()

    print(f"[load-generator] target={args.target} requests~={args.requests} concurrency={args.concurrency} duration<={args.duration}s")

    results = Counter()
    sem = asyncio.Semaphore(args.concurrency)
    deadline = time.time() + args.duration

    async with httpx.AsyncClient() as client:
        tasks = [
            asyncio.create_task(worker(client, args.target, results, deadline, sem))
            for _ in range(args.concurrency)
        ]
        # Also enforce a total-request ceiling independent of the time
        # deadline, so --requests is a real bound, not just advisory.
        sent = 0
        start = time.time()
        while sent < args.requests and time.time() < deadline:
            await asyncio.sleep(0.05)
            sent = sum(results.values())
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    elapsed = time.time() - start
    print(f"[load-generator] done in {elapsed:.1f}s — results: {dict(results)}")
    total = sum(results.values())
    if total == 0:
        print("[load-generator] WARNING: zero requests completed — target likely unreachable.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
