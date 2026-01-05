# experiments/ai_playground.py
"""
AI playground (optional).

This is NOT used by the deterministic audit pipeline.
It exists so you can experiment without mixing AI into your core logic.

How to run:
1) Install OpenAI SDK (optional):
   pip install openai

2) Set your API key in the environment (example for macOS/Linux):
   export OPENAI_API_KEY="..."

3) Run:
   python experiments/ai_playground.py
"""

from __future__ import annotations

import os

def main() -> int:
    try:
        from openai import OpenAI
    except Exception as e:
        print("OpenAI SDK not installed. Run: pip install openai")
        print(f"Details: {e}")
        return 2

    if not os.getenv("OPENAI_API_KEY"):
        print("Missing OPENAI_API_KEY environment variable.")
        return 2

    client = OpenAI()

    # Keep this separate from your audit logic. This is just a connectivity test.
    resp = client.responses.create(
        model="gpt-5",
        input="Say 'AI is working' in one sentence.",
    )

    # The SDK returns different shapes depending on version; output_text is common in recent versions.
    print(getattr(resp, "output_text", resp))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
