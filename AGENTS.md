# AGENTS.md

## Project Overview
Jekyll-based GitHub Pages slideshow using reveal.js. Static site, no database, no external services or credentials required.

## Setup Quirks
- Ruby 2.7 is required (github-pages 207 / Jekyll 3.9.0 era gems). Newer Ruby versions may fail to compile native extensions like nokogiri 1.10.8 and ffi 1.11.2.
- The full `ruby:2.7` image (not slim) is needed because gems like commonmarker require `make` and C build tools for native extensions.
- Gemfile.lock pins `BUNDLED WITH 1.17.3`. Install and use bundler 1.17.3 explicitly: `gem install bundler -v 1.17.3 && bundle _1.17.3_ install`.
- `--force_polling` is needed for file watching to work inside the Docker bind mount.

## Running
- `docker compose -f docker-compose.base44.yml up -d` starts Jekyll with livereload on port 3000.
- Healthcheck: `curl -sf http://localhost:3000/`
- Jekyll auto-regenerates on file changes; livereload refreshes the browser.

## Structure
- `_posts/` — slide content (one file per slide, dated 0000-01-01).
- `_layouts/presentation.html` — main layout wrapping reveal.js.
- `_includes/` — head, script, and slide partials.
- `node_modules/reveal.js/` — reveal.js presentation framework (vendored).
- `_config.yml` — Jekyll config with reveal.js settings.
