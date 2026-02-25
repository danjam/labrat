# TODO

- [ ] Cleanup docs
- [ ] Multi-model code review skill — Claude Code skill/hook inspired by [Code Council](https://github.com/klitchevo/code-council), routes diffs to multiple models via OpenRouter and synthesizes results
  - Free models: `qwen/qwen3-coder:free`, `deepseek/deepseek-r1-0528:free`, `meta-llama/llama-3.3-70b-instruct:free`, `mistralai/mistral-small-3.1-24b-instruct:free`, `google/gemini-2.0-flash-exp:free`
  - Gemini 2.5 Flash via BYOK (add `GEMINI_API_KEY` to OpenRouter dashboard under Keys → Integrations)
  - Rate limits on free tier: 20 req/min, 200 req/day
