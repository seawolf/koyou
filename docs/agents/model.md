# The on-device model

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before touching `web/wllama/`, `tool/fetch_wllama.sh`,
`lib/translation/on_device_backend*.dart`, `web_model.dart`, or the tagged
model tests.

## The web model tier

`web/wllama/` is staged by `tool/fetch_wllama.sh` and **not committed** — 9MB
of third-party browser build, for which npm is the source of truth. A build
without it degrades to the dictionary rather than failing, which is the same
contract a phone with no weights has, so do not add a hard error.

The version is pinned in that script for a reason. wllama's API changed shape
between majors and the failures are not readable:

- **`pathConfig` wants a `default` key** in 3.x, holding the URL of the single
  `wasm/wllama.wasm`. The 2.x `single-thread` / `multi-thread` keys throw
  `"default" is missing from pathConfig`.
- **`createCompletion` takes one options object**, llama.cpp-server shaped:
  `{prompt, n_predict, temperature, stop}`. There is no `nPredict`. Called the
  2.x way — `createCompletion(prompt, opts)` — the string lands where the
  options belong, the encoded worker message is garbage, and it surfaces as
  `RangeError: Invalid typed array length: 1163217991` from `runAction`
  reading a length out of the wasm heap. It looks like a broken model or a
  broken wasm and is neither.
- **`stop: ['\n']`** is a real stop sequence here, which the native side has to
  imitate by breaking out of its token stream.

Multi-threaded WASM needs `COOP`/`COEP` on the host for `SharedArrayBuffer`.
Not required where WebGPU is available, which is now every major browser.

The parts worth testing live in `web_model.dart`, which imports no
`dart:js_interop` and so runs on the VM with a fake engine. Keep it that way:
only the binding in `on_device_backend_web.dart` should need a browser.

## Running the model tests

Two suites are tagged off by default, because both need something the machine
may not have. Neither is part of `flutter test`:

```bash
# the Ollama harness — a laptop check against a real model, both directions
ollama serve & ollama pull qwen3.5:0.8b
flutter test --tags ollama

# the real shipping path: llama.cpp plus the real weights
KOUYU_LLAMA_LIB=/path/to/libllama.dylib \
KOUYU_LLAMA_MODEL=/path/to/Qwen3.5-0.8B-Q4_K_M.gguf \
flutter test --tags llama
```

Two traps in there, both of which cost an afternoon:

- **`flutter_test` replaces `HttpClient` with a mock that answers 400 to
  everything**, so a test cannot reach the network by accident. Any test that
  means to must set `HttpOverrides.global = null` first. Without it the Ollama
  test decided Ollama was absent and skipped itself while Ollama was running —
  a green suite that had checked nothing.
- **A hand-built `libllama` must match the revision `llama_cpp_dart` pins**,
  named in its README (currently tag `b10182`). Build HEAD instead and the
  struct layout of `llama_model_params` differs, so the FFI call crashes the
  isolate instead of failing cleanly. Android never hits this: the package
  bundles a `libllama.so` built at the pin.
