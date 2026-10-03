import { defineConfig } from 'cf/config';
import * as entrypoint from './worker.mjs' with { type: 'cf-worker' };

export default defineConfig({
  worker: {
    name: 'lyricise-installer',
    entrypoint,
    compatibilityDate: '2026-10-03',
    domains: ['lyricise.jsn.cam'],
  },
});
