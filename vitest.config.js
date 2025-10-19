import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "clarinet",
    singleThread: true,
    isolate: false,
    testTimeout: 60000,
  },
});
