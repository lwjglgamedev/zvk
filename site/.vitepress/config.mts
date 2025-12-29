import { defineConfig } from "vitepress";
import path from "node:path";

// https://vitepress.dev/reference/site-config
export default defineConfig({
  srcDir: "bookcontents",
  ignoreDeadLinks: true,
  title: "ZVK",
  description: "Vulkan graphics programming in Zig",
  vite: {
    resolve: {
      preserveSymlinks: true,
    },
    plugins: [
      {
        name: "resolve-relative-images",
        resolveId(source, importer) {
          if (
            (source.endsWith(".png") ||
              source.endsWith(".jpg") ||
              source.endsWith(".webp")) &&
            !source.startsWith(".") &&
            !source.startsWith("/") &&
            importer
          ) {
            const dir = path.dirname(importer);
            return path.resolve(dir, source);
          }
          return null;
        },
      },
    ],
  },
  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: "Home", link: "/" },
      { text: "Examples", link: "/markdown-examples" },
    ],

    sidebar: [
      {
        text: "Examples",
        items: [
          { text: "Markdown Examples", link: "/markdown-examples" },
          { text: "Runtime API Examples", link: "/api-examples" },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/vuejs/vitepress" },
    ],
  },
});
