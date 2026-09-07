// The browser side of the on-device model tier.
//
// Thin on purpose. Everything worth testing — the prompt, what of a reply is
// kept, when to decline — lives in Dart; this only owns the parts that cannot:
// dynamically importing wllama, WebGPU, and the OPFS cache the weights live in.
//
// Staged by tool/fetch_wllama.sh. If wllama is absent this file still loads and
// reports unsupported, so the web build degrades to the dictionary rather than
// failing — the same contract a phone with no weights has.
(() => {
  const WLLAMA = '/wllama/index.js';
  const WASM = '/wllama/wasm/wllama.wasm';

  const state = {
    module: null,
    wllama: null,
    loading: null,
    progress: 0,
    error: null,
  };

  const load = async () => {
    if (!state.module) state.module = await import(WLLAMA);
    return state.module;
  };

  window.kouyuModel = {
    // WebGPU is not required — wllama falls back to WASM — but it is the
    // difference between a translation and a wait, so it is reported.
    hasWebGpu: () => 'gpu' in navigator,

    async supported() {
      try {
        await load();
        return !!(navigator.storage && navigator.storage.getDirectory);
      } catch (e) {
        state.error = String(e && e.message ? e.message : e);
        return false;
      }
    },

    /// Bytes of this model already in the OPFS cache, or 0.
    async cachedBytes(url) {
      try {
        const { ModelManager } = await load();
        const models = await new ModelManager().getModels();
        const found = models.find((m) => m.url === url);
        return found ? found.size : 0;
      } catch (e) {
        return 0;
      }
    },

    progress: () => state.progress,
    error: () => state.error,
    ready: () => !!state.wllama,

    /// Downloads if needed and loads. Safe to call twice: the second call
    /// waits on the first rather than starting a second download.
    load(url, contextTokens) {
      if (state.wllama) return Promise.resolve(true);
      if (state.loading) return state.loading;
      state.loading = (async () => {
        try {
          state.error = null;
          const { Wllama } = await load();
          const wllama = new Wllama({ default: WASM });
          await wllama.loadModelFromUrl(url, {
            n_ctx: contextTokens,
            // Everything on the GPU where there is one; ignored otherwise.
            n_gpu_layers: 99,
            progressCallback: ({ loaded, total }) => {
              state.progress = total > 0 ? loaded / total : 0;
            },
          });
          state.wllama = wllama;
          state.progress = 1;
          return true;
        } catch (e) {
          state.error = String(e && e.message ? e.message : e);
          return false;
        } finally {
          state.loading = null;
        }
      })();
      return state.loading;
    },

    /// The raw reply. Dart decides what of it to keep.
    async translate(prompt, maxTokens) {
      if (!state.wllama) return null;
      try {
        const reply = await state.wllama.createCompletion({
          prompt,
          n_predict: maxTokens,
          temperature: 0,
          // A real stop sequence, which the native side has to imitate by
          // breaking out of its token stream.
          stop: ['\n'],
        });
        const choice = reply && reply.choices && reply.choices[0];
        return choice ? String(choice.text) : null;
      } catch (e) {
        state.error = String(e && e.message ? e.message : e);
        return null;
      }
    },

    // Whether the learner has switched the tier off. In localStorage rather
    // than a marker file, which is the native side's equivalent trick: it
    // describes the cached weights and needs no extra dependency.
    enabled: () => localStorage.getItem('kouyu.model.off') === null,

    setEnabled(on) {
      if (on) localStorage.removeItem('kouyu.model.off');
      else localStorage.setItem('kouyu.model.off', '1');
      return true;
    },

    async remove(url) {
      try {
        const { ModelManager } = await load();
        const manager = new ModelManager();
        for (const model of await manager.getModels()) {
          if (model.url === url) await model.remove();
        }
        if (state.wllama) {
          await state.wllama.exit();
          state.wllama = null;
        }
        state.progress = 0;
        return true;
      } catch (e) {
        state.error = String(e && e.message ? e.message : e);
        return false;
      }
    },
  };
})();
