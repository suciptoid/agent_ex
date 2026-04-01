# Changelog 2026-04-01

## LLM Streaming Timeout Increase
- Increased `req_llm`'s `stream_receive_timeout` to `60_000` in `config/config.exs`.
- This raises the wait window for streamed `{:next, ...}` chunk retrievals and should prevent the 30-second timeout seen in `GenServer.call/3`.
