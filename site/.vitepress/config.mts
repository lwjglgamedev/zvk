import { defineConfig } from "vitepress";
import path from "node:path";
import fs from "node:fs";

// Dynamically generate sidebar from chapter directories
function getChapterSidebar() {
  const bookcontentsPath = path.resolve(__dirname, "../../bookcontents");
  const chapters = fs
    .readdirSync(bookcontentsPath)
    .filter((dir) => dir.startsWith("chapter-"))
    .sort();

  return chapters.map((dir) => {
    const num = dir.replace("chapter-", "");
    const mdFile = path.join(bookcontentsPath, dir, `${dir}.md`);

    // Try to extract title from first heading in the markdown file
    let title = `Chapter ${num}`;
    if (fs.existsSync(mdFile)) {
      const content = fs.readFileSync(mdFile, "utf-8");
      const match = content.match(/^#\s+(.+)$/m);
      if (match) {
        title = match[1];
      }
    }

    return {
      text: title,
      link: `/${dir}/${dir}`,
    };
  });
}

// https://vitepress.dev/reference/site-config
export default defineConfig({
  srcDir: "bookcontents",
  ignoreDeadLinks: [/booksamples/],
  rewrites: {
    "README.md": "index.md",
  },
  title: "ZVK",
  description: "Vulkan graphics programming in Zig",
  markdown: {
    config: (md) => {
      // Transform booksamples links before VitePress processes them
      const defaultRender =
        md.renderer.rules.link_open ||
        ((tokens, idx, options, _env, self) =>
          self.renderToken(tokens, idx, options));

      md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
        const hrefIndex = tokens[idx].attrIndex("href");
        if (hrefIndex >= 0) {
          const href = tokens[idx].attrs![hrefIndex][1];
          if (href.includes("booksamples/chapter-")) {
            const match = href.match(/booksamples\/(chapter-\d+)/);
            if (match) {
              tokens[idx].attrs![hrefIndex][1] =
                `https://github.com/lwjglgamedev/zvk/tree/main/booksamples/${match[1]}`;
            }
          }
        }
        return defaultRender(tokens, idx, options, env, self);
      };
    },
  },
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
    nav: [{ text: "Home", link: "/" }],

    sidebar: [
      {
        text: "Chapters",
        items: getChapterSidebar(),
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/vuejs/vitepress" },
    ],
  },
});
