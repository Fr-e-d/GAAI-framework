import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    exclude: [
      'node_modules/**',
      'workers/posthog-proxy/**',
      'workers/satellite/**',
      '**/node_modules/**',
    ],
  },
});
