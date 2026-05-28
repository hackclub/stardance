# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

user = User.find_or_create_by!(email: "kartikey@hackclub.com", slack_id: "U05F4B48GBF")
user.grant_role!(:super_admin)
user.grant_role!(:admin)

# ---------------------------------------------------------------------------
# Seed missions
#
# A small set of starter missions matching the examples in
# docs/missions-design.md. Idempotent: re-running upserts the row and replaces
# its steps so the seed stays in sync with edits to this file.
# ---------------------------------------------------------------------------

seed_missions = [
  {
    slug: "home-panel-webdev",
    name: "Build a personal home panel",
    difficulty: "beginner",
    description: <<~MD,
      Make a customizable web dashboard you'd actually open as your browser's home page —
      think weather, tasks, quick links, anything that matters to *you*. Frontend, backend,
      or both. Deploy it somewhere reachable.
    MD
    achievement_name: "Home Panel Builder",
    achievement_description: "Shipped a personal home-page dashboard.",
    steps: [
      {
        title: "Pick what goes on the panel",
        body: <<~MD
          ### Goal
          End this step with a written plan committed to your repo so future-you can't bikeshed forever.

          ### Why this matters
          A home panel only earns its slot if you'd open it daily. The fastest way to build something nobody uses is to start with what's *technically interesting* instead of what's *personally useful*. So we pick widgets first, then build.

          ### Tools you'll want

          | Tool | Why |
          | --- | --- |
          | A scratch doc (Notion, Markdown, paper) | Capture your widget ideas without losing them |
          | Your real browser history | Surface the data you already check daily |
          | Pen + paper, or [Excalidraw](https://excalidraw.com) | A 2-minute sketch beats a 2-hour Figma |

          ### Challenges

          1. **Audit yourself.** Look at your last week of browser history. Which 3–5 things did you check the most? Weather? Calendar? GitHub notifications? A dashboard for a side project? Write them down.
          2. **Pick widgets ruthlessly.** Cross out anything you wouldn't *miss* if it was gone. If you have more than 5, cut deeper. A boring panel you actually open beats a busy panel you don't.
          3. **Sketch the layout.** Doesn't matter how — napkin, Figma, ASCII art. The point is to know roughly where each widget lives before you write CSS.
          4. **Commit the plan.** Drop the sketch (photo or file) into a `PLAN.md` at the root of your repo. Push it.

          > 💡 **Hint** — if you're stuck on what to include, pick *one* "live data" widget (weather, time, a feed), *one* "quick action" widget (links, search, todos), and stop there. Add more in step 3 if you have time.

          ### Done when
          - `PLAN.md` exists in your repo with a list of widgets and a layout sketch.
          - You'd be embarrassed to remove any of the widgets you picked.
        MD
      },
      {
        title: "Get one widget rendering live data",
        body: <<~MD
          ### Goal
          Pick the *one* widget from your plan you'd miss most, and get it rendering with real, live data end-to-end.

          ### Why now, not all of them
          Because every widget you build runs into the same kinds of problems: fetching, error states, loading, re-rendering. Solving them once with a real example beats solving them five times with placeholder data.

          ### Suggested stacks

          - **Just HTML/CSS/JS** — fine if your widget is a simple fetch. Ship a static page with `fetch()` calls.
          - **A framework** — Next.js, SvelteKit, Astro, Remix, whatever you've been wanting to try. Pick one you're curious about.
          - **A backend** — only if your widget needs a secret (API key, OAuth). Otherwise skip it for now.

          ### Challenges

          1. **Pick the API.** If your widget needs data, find an API you can call without paying for a plan. Public, no-auth APIs are gold here ([open-meteo.com](https://open-meteo.com) for weather, GitHub's REST API, RSS feeds via [rss2json](https://rss2json.com), etc).
          2. **Get a "hello data" rendering.** Just dump the raw JSON onto the page first. Don't style it.
          3. **Style the actual widget.** Now that you trust the data flow, make it look like the sketch from step 1.
          4. **Handle one failure path.** Network down? API rate-limited? Pick *one* failure case and render something that isn't a white screen of death.

          > 💡 **Hint** — keep the secret at the bottom of your todo list. Most "look, a real widget" demos use APIs that need no auth at all. Save OAuth for after this mission.

          ### Done when
          - The widget shows current real data.
          - You've reloaded the page 3+ times and it still works.
          - When you kill your wifi and reload, it shows a non-broken fallback.
        MD
      },
      {
        title: "Make it your home page",
        body: <<~MD
          ### Goal
          Deploy the panel and use it as your actual browser home page for a week. The point of this mission is *use*, not just *build*.

          ### Pick a host

          | Host | Good for |
          | --- | --- |
          | Vercel / Netlify | Anything frontend-only or a JS framework |
          | Cloudflare Pages | Same, slightly leaner free tier |
          | A VPS you already have | Full backend, custom domains, full control |
          | GitHub Pages | Pure static — no API keys in the bundle though |

          ### Challenges

          1. **Deploy.** Get it live on a public URL. Test it from a different network (mobile data) so you know it actually works for not-just-localhost-you.
          2. **Set it as your home page.** Chrome: Settings → On startup → Open a specific page. Same idea in Firefox / Safari. Open a new tab and confirm it shows up.
          3. **Use it for a week.** Genuinely. Don't open Twitter first. Catch yourself reflexively typing the URL of whatever you used to open and re-route to your panel.
          4. **Keep notes.** What annoys you? What's missing? What surprised you? Save these for the writeup in step 4.

          > ⚠️ **Watch out** — if your widget needs an API key, don't ship it in client-side JS. Either proxy through a tiny serverless function or pick an API that doesn't need auth.

          ### Done when
          - The panel is at a stable public URL you've shared with at least one person.
          - It's been your homepage for at least 5 days.
          - You have at least 3 "this is annoying" notes in a scratch file.
        MD
      },
      {
        title: "Ship the writeup",
        body: <<~MD
          ### Goal
          Post a devlog that captures what you built, what surprised you, and what you'd do differently. Then ship the project.

          ### What goes in the writeup

          - **One paragraph intro.** What is it? Why'd you build it?
          - **The widgets.** A line each, with a screenshot or two.
          - **Surprises.** From your week of using it — both good ("I check weather way less now") and bad ("turns out free-tier weather APIs round to the nearest hour").
          - **What's next.** Either "I'm done, here's the link" or "I'd add X, Y, Z if I keep going."

          ### Challenges

          1. **Take screenshots.** Real ones, with your real data. Crop tightly. If something looks ugly in screenshots, fix the ugly thing now.
          2. **Write the devlog.** Use the bullets above as a skeleton. Aim for 200–400 words — enough to be specific, short enough to actually finish.
          3. **Ship the project.** Hit ship and submit it to this mission.

          ### Done when
          - The devlog is posted with at least one screenshot.
          - The project is shipped.
          - You'd happily send the link to a friend who wanted to build something similar.
        MD
      }
    ]
  },
  {
    slug: "wario-ware-clone",
    name: "WarioWare-style microgame collection",
    difficulty: "intermediate",
    description: <<~MD,
      Build a collection of bite-sized microgames in the WarioWare spirit: each game lasts
      a few seconds, ramps up in speed, and is judged on how *fun* the chaos feels.
      Pick any engine or framework — web, Godot, Unity, raw canvas, doesn't matter.

      This one is intentionally loose — surprise us.
    MD
    achievement_name: "Microgame Maestro",
    achievement_description: "Shipped a WarioWare-style microgame collection.",
    steps: []
  },
  {
    slug: "browser-extension-starter",
    name: "Build a browser extension",
    difficulty: "beginner",
    description: <<~MD,
      Ship a browser extension that does one useful thing well. Could be a tab manager,
      a custom new-tab page, a price-tracker, a privacy thing — whatever scratches an
      itch. Submit it to the Chrome Web Store, Firefox Add-ons, or both.
    MD
    achievement_name: "Extension Author",
    achievement_description: "Shipped a published browser extension.",
    steps: [
      { title: "Pick a problem",
        body: "Write down the one thing your extension will do. If you can't explain it in one sentence, pick a smaller scope." },
      { title: "Get the manifest loading",
        body: "Stand up a manifest v3 extension that loads in your browser of choice without errors. Hello-world UI is fine here." },
      { title: "Make it actually do the thing",
        body: "Wire up the real functionality. Test it on at least three real pages or workflows." },
      { title: "Submit to a store",
        body: "Pay the listing fee or use a free dev account, fill out the listing, and submit. Ship the project once it's live (or queued for review)." }
    ]
  },
  {
    slug: "discord-slack-bot-starter",
    name: "Discord or Slack bot starter",
    difficulty: "intermediate",
    description: <<~MD,
      Build a bot that does something genuinely useful for a server you're already in.
      Slash commands, scheduled messages, integration with an external API — pick one
      core feature and nail it. Host it somewhere always-on.
    MD
    achievement_name: "Bot Wrangler",
    achievement_description: "Shipped a hosted Discord or Slack bot.",
    steps: [
      { title: "Pick the platform and scope",
        body: "Discord or Slack? What's the one feature? Get permission from a server admin if you don't run the server yourself." },
      { title: "Get an empty bot online",
        body: "Register the app, invite it to a test server, and respond to a single hello-world command from a deployed (not-localhost) host." },
      { title: "Build the real feature",
        body: "Implement the actual feature. Handle auth, rate limits, and at least one error path." },
      { title: "Document and ship",
        body: "Write a setup guide, a list of commands, and a one-screenshot demo. Then ship the project." }
    ]
  },
  {
    slug: "build-your-own-scripting-language",
    name: "Build your own scripting language",
    difficulty: "advanced",
    description: <<~MD,
      Design and implement a tiny scripting language. Lexer, parser, and either a
      tree-walking interpreter or a tiny VM. Pick the smallest interesting feature set
      that's still recognizably a language: variables, conditionals, functions, loops.

      Advanced mission — loose by design. Surprise us with what your language does well.
    MD
    achievement_name: "Language Designer",
    achievement_description: "Shipped a working scripting-language implementation.",
    steps: []
  }
]

seed_missions.each do |attrs|
  steps_attrs = attrs.delete(:steps) || []

  mission = Mission.unscoped.find_or_initialize_by(slug: attrs[:slug])
  mission.assign_attributes(attrs.merge(deleted_at: nil, enabled: true))
  mission.save!

  # Replace step set so edits to seeds.rb sync down. Hard delete here
  # (not soft) since these rows are seed-managed, not user-managed.
  mission.steps.unscoped.where(mission_id: mission.id).delete_all
  steps_attrs.each_with_index do |step_attrs, idx|
    mission.steps.create!(step_attrs.merge(position: idx + 1))
  end
end

puts "Seeded #{seed_missions.size} missions."

# Enable core feature flags for development/staging
if Rails.env.development? || Rails.env.staging?
  Flipper.enable(:shop_open)
  Flipper.enable(:voting)
  Flipper.enable(:grant_stardust)
end

# Seed default shop items
ShopItem::FreeStickers.find_or_create_by!(name: "Stickers!!") do |item|
  item.description = "we'll actually send you these!"
  item.ticket_cost = 10
  item.enabled = true
  item.one_per_person_ever = true
  item.enabled_xx = true
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/free_sticker.avif")),
    filename: "free_sticker.avif",
    content_type: "image/avif"
  )
end

ShopItem::TutorialNothing.find_or_create_by!(name: "Nothing") do |item|
  item.description = "Skip the freebie — just learn how the shop works."
  item.ticket_cost = 0
  item.enabled = true
  item.one_per_person_ever = true
  item.unlisted = true
  item.enabled_xx = true
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/idea/question.png")),
    filename: "tutorial_nothing.png",
    content_type: "image/png"
  )
end
