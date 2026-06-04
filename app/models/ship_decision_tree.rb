module ShipDecisionTree
  ROOT_ID = "root".freeze

  # The tree is a flat hash of nodes keyed by id. Each node is either a
  # `:question` (with `choices`) or a `:leaf` (with `content`). Children
  # reference parent ids so we can rebuild the breadcrumb client-side.
  #
  # Adding a new branch: pick a new id, add a node here, and reference it
  # from a parent's `choices`. No JS changes required.
  NODES = {
    "root" => {
      type: :question,
      parent: nil,
      question: "What did you build?",
      intro: "Pick the closest match. We'll narrow down from there — most projects only need two or three clicks to land on tailored advice.",
      choices: [
        { id: "software", emoji: "💻", title: "Software you run", subtitle: "Apps, websites, games, libraries — anything that runs on a computer or phone." },
        { id: "hardware", emoji: "🔌", title: "Hardware", subtitle: "PCBs, mechanical builds, embedded firmware, 3D-printed designs." },
        { id: "addon",    emoji: "🧩", title: "An add-on for an existing platform", subtitle: "Browser extensions, game mods, Discord/Slack bots, plugins." },
        { id: "oss",      emoji: "🤝", title: "A contribution to an existing open-source project", subtitle: "PRs you opened on someone else's project." },
        { id: "other",    emoji: "✨", title: "Something else / I'm not sure", subtitle: "Creative work, experimental stuff, or things that don't fit the boxes above." }
      ]
    },

    # ---- Software branch ------------------------------------------------

    "software" => {
      type: :question,
      parent: "root",
      question: "What kind of software?",
      choices: [
        { id: "software.web",     emoji: "🌐", title: "Web app or website", subtitle: "Anything that runs in a browser at a URL." },
        { id: "software.game",    emoji: "🎮", title: "A game",             subtitle: "We'll ask how people play it next." },
        { id: "software.mobile",  emoji: "📱", title: "Mobile app",         subtitle: "iOS, Android, or cross-platform." },
        { id: "software.desktop", emoji: "🖥️", title: "Desktop app",        subtitle: "Native or Electron, runs on Windows / Mac / Linux." },
        { id: "software.cli",     emoji: "⌨️", title: "CLI tool, library, or framework", subtitle: "Something other developers use." }
      ]
    },

    "software.web" => {
      type: :leaf,
      parent: "software",
      title: "Shipping a web app or website",
      intro: "These are the easiest to ship well, and the easiest to ship badly. The bar is: someone clicks a link and uses your site without running any commands.",
      shipped_means: "Your site is deployed at a public URL. Anyone with the link can open it and see something working.",
      demo_options: [
        "<strong>Vercel, Netlify, or Cloudflare Pages</strong> for anything modern — Next.js, SvelteKit, Astro, plain static.",
        "<strong>GitHub Pages</strong> for static sites — fine for vanilla HTML/CSS/JS or built SPAs.",
        "<strong><a href='https://nest.hackclub.com/' target='_blank' rel='noopener'>Nest</a></strong> is recommended for projects with a backend or database. Paid tiers on Render or Railway are also good, but avoid their free tiers since they suffer from slow cold starts and aren't guaranteed to keep your app online indefinitely.",
        "A custom domain is a nice touch but not required."
      ],
      readme_must_haves: [
        "One-line description at the top.",
        "Live demo link (the one you put in the demo URL field, mirrored here).",
        "Screenshot or short GIF — voters skim these.",
        "How to run it locally if someone wants to."
      ],
      common_flags: [
        "Demo URL is the GitHub repo, not the deployed site — the most common reason web projects bounce.",
        "Site loads but the main feature is broken. Test the deployed build, not just localhost.",
        "Site requires a login but you didn't share credentials. Either provide a demo account or remove the gate for the demo."
      ],
      examples: [
        { name: "saasheaven.space",            url: "https://www.saasheaven.space/",         note: "TypeScript, deployed at a custom domain. Clear what it does within five seconds." },
        { name: "TablissNG (browser new tab)", url: "https://bookcatkid.github.io/TablissNG/", note: "Pure GitHub Pages, no backend." }
      ]
    },

    "software.game" => {
      type: :question,
      parent: "software",
      question: "How will people play it?",
      choices: [
        { id: "software.game.web",      emoji: "🕹️", title: "In a browser", subtitle: "WebGL build, HTML5 canvas, etc." },
        { id: "software.game.download", emoji: "⬇️", title: "Download and install", subtitle: "Native build for desktop or mobile." },
        { id: "software.game.handheld", emoji: "🎲", title: "On a console / handheld", subtitle: "Sprig, Game Boy, custom hardware." }
      ]
    },

    "software.game.web" => {
      type: :leaf,
      parent: "software.game",
      title: "Shipping a browser-playable game",
      intro: "By far the lowest-friction way to ship a game. Your demo URL is a link, voters click, they're playing in ten seconds.",
      shipped_means: "Someone can open your itch.io page (or equivalent), hit play, and your game runs in their browser.",
      demo_options: [
        "<strong>itch.io</strong> — the dominant choice. Free, supports HTML5/WebGL/Unity/Godot exports.",
        "<strong>GitHub Pages</strong> for hand-rolled HTML5 games.",
        "A custom site with the game embedded, if you want more control."
      ],
      readme_must_haves: [
        "What the game is, in one sentence.",
        "Link to play it.",
        "Controls — even the ones you think are obvious.",
        "A screenshot or two — the cover art on itch.io counts."
      ],
      common_flags: [
        "Game requires a download but the page says 'play in browser'. Match the link to reality.",
        "Asset license problems — ripped sprites, music without permission. Use CC0 / free assets or your own.",
        "Build broke during export. Test the deployed itch build before submitting, not just the editor."
      ]
    },

    "software.game.download" => {
      type: :leaf,
      parent: "software.game",
      title: "Shipping a downloadable game",
      intro: "When your game can't run in a browser — Unity native, Godot native, GameMaker, Ren'Py — voters need a build they can download and run.",
      shipped_means: "There's a downloadable build for at least one platform, and clear instructions for getting it running.",
      demo_options: [
        "<strong>itch.io with a downloadable build</strong> — same upload flow, just zip the platform exports.",
        "<strong>GitHub Releases</strong> with platform-specific archives.",
        "Both at once is fine — itch for ease, GitHub for trust."
      ],
      readme_must_haves: [
        "Which platforms are supported.",
        "How to actually run it once downloaded — especially on macOS, where voters won't know how to bypass Gatekeeper without help.",
        "Screenshots and ideally a 30-second gameplay video. Most voters won't download.",
        "Controls."
      ],
      common_flags: [
        "macOS build is unsigned and refuses to open. Either sign it, or include exact instructions (right-click → open, or a terminal command).",
        "Build is huge (>500 MB) and takes ten minutes to download. Compress assets or split optional content.",
        "Only ships a Windows build but voters are on Mac/Linux. At minimum, include a gameplay video so non-Windows voters can still rate."
      ]
    },

    "software.game.handheld" => {
      type: :leaf,
      parent: "software.game",
      title: "Shipping a console / handheld game",
      intro: "If you built for Sprig, a Game Boy, custom hardware, or anything that doesn't run on a phone or PC, the bar shifts to 'show me clearly that this works'.",
      shipped_means: "There's a way to either run your game in an emulator/simulator OR a clear video proving it works on the real device.",
      demo_options: [
        "<strong>Emulator demo</strong> — most retro/embedded games have a web emulator. Sprig has its own.",
        "<strong>GitHub Release</strong> with the ROM / binary, plus instructions for which emulator to use.",
        "<strong>Always include a video</strong> of it running on the real hardware — the single highest-impact thing for review."
      ],
      readme_must_haves: [
        "Target hardware (Sprig, GBA, custom board model, etc.).",
        "How to flash / load it.",
        "Video of it running on real hardware.",
        "Controls."
      ],
      common_flags: [
        "Only the binary, no video — review can't verify it actually works on the device.",
        "Demo URL is just the repo. The repo shouldn't be the demo; link to a release or a video."
      ]
    },

    "software.mobile" => {
      type: :leaf,
      parent: "software",
      title: "Shipping a mobile app",
      intro: "iOS or Android. Your goal is: voters can either install your app or watch it work without weird friction.",
      shipped_means: "There's a way to install your app. Ideally a store listing; if that's not feasible, a signed APK and clear sideload instructions.",
      demo_options: [
        "<strong>Play Store</strong> internal/closed testing, or a full release for Android.",
        "<strong>App Store</strong> via TestFlight (free — no $99 needed for closed testing), or a full release for iOS.",
        "<strong>Signed APK</strong> in a GitHub Release for Android, with sideload instructions.",
        "If you can't ship a build at all, a 60-second screen recording is acceptable — but a last resort."
      ],
      readme_must_haves: [
        "Platforms supported and minimum OS version.",
        "Install link or instructions.",
        "Screenshots — voters who can't or won't install rely entirely on these.",
        "What permissions it needs and why."
      ],
      common_flags: [
        "APK is unsigned, Android refuses to install. Sign with a debug key at minimum.",
        "Play Store / TestFlight link only works for invited testers and you didn't open the testing track up. Use closed testing with a public link or share a build directly.",
        "App needs a backend that's offline. Keep the backend running for review and voting."
      ]
    },

    "software.desktop" => {
      type: :leaf,
      parent: "software",
      title: "Shipping a desktop app",
      intro: "Native or Electron app for Windows, macOS, or Linux. Reviewers and voters don't want to compile from source.",
      shipped_means: "A pre-built binary exists for at least one platform, with a clear path from 'click link' to 'app is running'.",
      demo_options: [
        "<strong>GitHub Releases</strong> with installers (.dmg, .exe, .AppImage, .deb, etc.) for the platforms you support.",
        "<strong>Microsoft Store / Mac App Store</strong> for shipping with auto-update and signing baked in.",
        "<strong>Homebrew</strong> or an apt repository if you want to be fancy."
      ],
      readme_must_haves: [
        "Platform support matrix.",
        "Install instructions per platform.",
        "Screenshots of the running app.",
        "How to launch it on macOS without Gatekeeper screaming (very common confusion)."
      ],
      common_flags: [
        "Releases page exists but is empty or only has source zips. Build platform binaries before shipping.",
        "App needs a config file you didn't include. Default to a working state out of the box."
      ]
    },

    "software.cli" => {
      type: :leaf,
      parent: "software",
      title: "Shipping a CLI tool, library, or framework",
      intro: "Tools other developers use. Your audience is technical, but the bar is still: I can install and use this in five minutes.",
      shipped_means: "Your tool is published to a real package registry, OR there's a working binary release with one-command install instructions.",
      demo_options: [
        "<strong>Package registries</strong> — npm (Node), PyPI (Python), crates.io (Rust), Homebrew (macOS CLI), apt (Debian/Ubuntu).",
        "<strong>GitHub Releases</strong> with prebuilt binaries for major platforms.",
        "A short asciinema recording of the tool in action — counts as a demo for CLI projects."
      ],
      readme_must_haves: [
        "One-line description at the top — what it does, who it's for.",
        "Install command in a code block.",
        "Quick start — the first thing users will run.",
        "Either an asciinema cast or an animated GIF of it working."
      ],
      common_flags: [
        "README is just the auto-generated help text. Write a real intro for humans.",
        "Tool requires obscure system dependencies you didn't list. Spell them out.",
        "No published package, just a 'clone and cargo build' instruction. Publish to the registry if you can."
      ]
    },

    # ---- Hardware branch ------------------------------------------------

    "hardware" => {
      type: :question,
      parent: "root",
      question: "What kind of hardware?",
      choices: [
        { id: "hardware.electronics", emoji: "🔧", title: "PCB / electronics", subtitle: "Schematic + board you designed and (ideally) built." },
        { id: "hardware.mechanical",  emoji: "🪛", title: "3D-printed or mechanical", subtitle: "Printable parts, mechanisms, enclosures." },
        { id: "hardware.firmware",    emoji: "📡", title: "Embedded firmware", subtitle: "Code that runs on a microcontroller (Arduino, ESP32, RP2040, etc.)." }
      ]
    },

    "hardware.electronics" => {
      type: :leaf,
      parent: "hardware",
      title: "Shipping a PCB / electronics project",
      intro: "Hardware is the category most likely to bounce on review, almost always for one reason: no demo. Reviewers can't physically have your board, so you have to show it works.",
      shipped_means: "There's a clear, public design (schematic + board files), photos of the assembled hardware, and a video of it doing the thing.",
      demo_options: [
        "<strong>KiCanvas</strong> link to view the PCB in-browser — great for reviewers.",
        "<strong>Photos</strong> of the assembled board, ideally with the cover off.",
        "<strong>Video of it working</strong> — non-negotiable for hardware. 30–60 seconds is plenty.",
        "Optionally a Printables / GitHub Release with Gerbers / a 3D-printable enclosure."
      ],
      readme_must_haves: [
        "BOM (bill of materials) — what parts you used.",
        "Where the design files live (KiCad project, EasyEDA link, etc.).",
        "Photos of assembly steps if relevant.",
        "Embedded video or animated GIF."
      ],
      common_flags: [
        "Demo URL is the GitHub repo with no images. Reviewers have no way to see it works.",
        "No video. Photos alone aren't enough to show function — only that you have a board.",
        "Schematic isn't published — only board photos. Both matter."
      ]
    },

    "hardware.mechanical" => {
      type: :leaf,
      parent: "hardware",
      title: "Shipping a 3D-printed or mechanical project",
      intro: "Whether it's a printable model, a mechanism, or an enclosure, the goal is for someone else to be able to actually print or build it.",
      shipped_means: "Your design files are public, printable/buildable, and there's photo/video proof of the finished thing.",
      demo_options: [
        "<strong>Printables</strong> — the dominant choice. Upload STLs, write up the print, link it from your demo URL.",
        "<strong>Onshape</strong> public document for parametric CAD.",
        "<strong>GitHub Release</strong> with STLs and a printer-settings note."
      ],
      readme_must_haves: [
        "Photos of the assembled / printed result.",
        "Print settings (layer height, supports, infill) if relevant.",
        "BOM for any non-printed parts (screws, bearings, motors).",
        "Assembly instructions if multi-part."
      ],
      common_flags: [
        "Only renders, no real photos. Renders look good but reviewers want proof.",
        "STL is included but no print settings — beginners following along will fail.",
        "Mechanism shown statically, not in motion. Add a short video."
      ]
    },

    "hardware.firmware" => {
      type: :leaf,
      parent: "hardware",
      title: "Shipping embedded firmware",
      intro: "Code that runs on a microcontroller. The audience is people who probably have similar hardware sitting around.",
      shipped_means: "Source is public, there's a flashable build (or clear build instructions), and a video shows it running on real hardware.",
      demo_options: [
        "<strong>GitHub Release</strong> with the precompiled .uf2 / .hex / .bin.",
        "<strong>Wokwi simulator</strong> link if your project runs there — counts as a fully playable demo.",
        "<strong>Video</strong> of the device doing its thing."
      ],
      readme_must_haves: [
        "Target hardware (board, MCU model).",
        "How to flash it.",
        "Pin / wiring diagram if there are external components.",
        "Video of it running."
      ],
      common_flags: [
        "Source only, no precompiled binary, and no video. Reviewers can't verify.",
        "Wiring isn't documented — works for you, no one else can replicate."
      ]
    },

    # ---- Add-on branch --------------------------------------------------

    "addon" => {
      type: :question,
      parent: "root",
      question: "What's it for?",
      choices: [
        { id: "addon.browser",  emoji: "🧭", title: "Browser extension",                 subtitle: "Chrome, Firefox, Safari, Edge." },
        { id: "addon.gamemod",  emoji: "🟫", title: "Game mod",                            subtitle: "Minecraft, GameMaker, Sky Factory, etc." },
        { id: "addon.bot",      emoji: "🤖", title: "Discord or Slack bot / app",          subtitle: "Anything that lives inside a chat platform." },
        { id: "addon.plugin",   emoji: "🔌", title: "Plugin for another tool",             subtitle: "VS Code, Obsidian, OBS, Figma, Blender, etc." }
      ]
    },

    "addon.browser" => {
      type: :leaf,
      parent: "addon",
      title: "Shipping a browser extension",
      intro: "Extensions live in stores. Voters install or skip — there's no middle ground.",
      shipped_means: "Your extension is either published to the official store, or there's a packaged build a voter can sideload in 30 seconds.",
      demo_options: [
        "<strong>Chrome Web Store</strong> listing.",
        "<strong>Firefox Add-ons (AMO)</strong> listing.",
        "<strong>GitHub Release</strong> with the packaged extension + clear sideload instructions (<code>chrome://extensions</code> → Load unpacked).",
        "A 30-second screen recording of the extension in use, in case voters won't install."
      ],
      readme_must_haves: [
        "What it does, in two sentences max.",
        "Install link.",
        "Screenshots showing the extension in action on a real page.",
        "What permissions it needs and why."
      ],
      common_flags: [
        "Manifest V3 issues — extension installs but doesn't run because of API changes. Test in a clean browser.",
        "Permissions are way too broad ('access all sites') without justification."
      ]
    },

    "addon.gamemod" => {
      type: :leaf,
      parent: "addon",
      title: "Shipping a game mod",
      intro: "Mods need to be installable on the actual game, with clear version compatibility.",
      shipped_means: "Your mod is published on the game's primary mod platform, or there's a packaged build with install instructions and version-pinned compatibility info.",
      demo_options: [
        "<strong>Modrinth</strong> for Minecraft mods.",
        "<strong>CurseForge</strong> for Minecraft / WoW / etc.",
        "<strong>Steam Workshop</strong> for Steam games that support it.",
        "<strong>GitHub Release</strong> with packaged mod files."
      ],
      readme_must_haves: [
        "Game and version compatibility.",
        "Required loader (Fabric, Forge, etc.) for Minecraft.",
        "Install instructions.",
        "Screenshots or video of the mod in action."
      ],
      common_flags: [
        "Mod was tested on one version, breaks on others, but the README claims wide compatibility.",
        "Install requires editing config files but you didn't document them."
      ]
    },

    "addon.bot" => {
      type: :leaf,
      parent: "addon",
      title: "Shipping a Discord or Slack bot",
      intro: "Bots that need to be running don't ship well if you turn them off. Either keep them running on a free tier, or invite voters into a server where they can be tried.",
      shipped_means: "There's a way to actually use the bot — either an invite link or a working live deployment in a public server.",
      demo_options: [
        "<strong>Discord</strong> — a bot invite link with the right scopes, plus an invite to a public test server.",
        "<strong>Slack</strong> — a link to add the app to a workspace, or to join a public test workspace.",
        "<strong>Self-host instructions</strong> if you can't keep it running — but be honest about it being offline."
      ],
      readme_must_haves: [
        "Slash command list / how to use it.",
        "Required permissions / scopes.",
        "Self-host instructions if applicable.",
        "Screenshots of the bot in action."
      ],
      common_flags: [
        "Bot is offline by the time review happens. Keep it running until your project is voted out.",
        "Invite link uses 'admin' scope when the bot only needs message permissions. Reviewers will flag this."
      ]
    },

    "addon.plugin" => {
      type: :leaf,
      parent: "addon",
      title: "Shipping a plugin for another tool",
      intro: "Plugins for editors, design tools, or creative apps. The host platform usually has a marketplace — use it.",
      shipped_means: "Your plugin is published to the host's marketplace, or there's a packaged build + clear install path.",
      demo_options: [
        "<strong>Host marketplace</strong> — VS Code Marketplace, Figma Community, Obsidian community plugins, etc.",
        "<strong>GitHub Release</strong> with the packaged plugin + sideload instructions.",
        "<strong>Video</strong> of the plugin doing its thing inside the host tool."
      ],
      readme_must_haves: [
        "Host tool + minimum version.",
        "Install link / instructions.",
        "Screenshots showing the plugin's UI inside the host tool.",
        "How to invoke it (command palette, hotkey, button)."
      ],
      common_flags: [
        "Plugin works in dev mode but the packaged version is broken. Test the package, not just the source.",
        "Doesn't say which host versions are supported."
      ]
    },

    # ---- OSS / other ----------------------------------------------------

    "oss" => {
      type: :leaf,
      parent: "root",
      title: "Shipping an open-source contribution",
      intro: "If you contributed to someone else's project — a real PR they merged, or one waiting on review — that's a valid Stardance ship. The bar shifts: the demo isn't yours, the work is.",
      shipped_means: "There's a link to your specific contribution (PR, patch series, issue with code attached), and clear documentation of what you actually did.",
      demo_options: [
        "<strong>Link to the merged PR</strong>, or the open PR if it's awaiting review.",
        "<strong>Link to the upstream project's live demo</strong>, so reviewers can see what your contribution affects.",
        "Optionally a fork with your changes deployed, if the upstream isn't easy to test against."
      ],
      readme_must_haves: [
        "Which project you contributed to, and a one-line description of it.",
        "Direct link to your PR(s).",
        "What your contribution does — feature, bug fix, refactor, docs?",
        "Before / after screenshots if it's a UI change.",
        "If the PR isn't merged yet: review status and any maintainer feedback so far."
      ],
      common_flags: [
        "PR is a typo fix or single-line whitespace change. Stardance contributions need real engineering work — usually five or more hours.",
        "Linked PR isn't actually yours (it's from another contributor). Double-check the author.",
        "PR is open but stale and the maintainer hasn't responded. Worth a polite ping before shipping."
      ],
      examples: [
        { name: "Haiku OS contribution",   url: "https://review.haiku-os.org/c/haiku/+/10396", note: "Real OS-level patches with maintainer review." },
        { name: "Zod Playground contribution", url: "https://github.com/marilari88/zod-playground", note: "Multiple merged PRs adding features." }
      ]
    },

    "other" => {
      type: :leaf,
      parent: "root",
      title: "Shipping something that doesn't fit the categories",
      intro: "Custom hardware, an OS kernel, a research artifact, a creative coding piece — sometimes your project just doesn't have a 'demo URL' in the normal sense. That's OK. The bar is unchanged: a stranger has to be able to see that it's real and works.",
      shipped_means: "There's a way for someone to experience or verify your project that doesn't require them to have your exact setup.",
      demo_options: [
        "<strong>Video demo</strong> — 90–180 seconds on YouTube or Vimeo, showing the thing working end-to-end.",
        "<strong>Emulator / simulator</strong> if your project targets unusual hardware (e.g. <code>copy.sh/v86</code> for OS images).",
        "A written walkthrough with annotated screenshots, if the artifact is the documentation itself.",
        "Live performance / installation? A recorded session counts."
      ],
      readme_must_haves: [
        "Honest description of what the project is, including limitations.",
        "Why a normal demo wasn't possible.",
        "Whatever stand-in you chose (video, emulator link, screenshots).",
        "How to actually get it running if someone really wants to."
      ],
      common_flags: [
        "Reaches for the 'video demo' escape hatch when a real demo would have been possible.",
        "Video is unlisted but no link in the README. Reviewers won't dig.",
        "Long video with no edit. Cut to the parts that demonstrate the project working."
      ]
    }
  }.freeze

  # Returns the JSON payload the Stimulus controller consumes.
  def self.serialized
    NODES.transform_values do |node|
      node.merge(type: node[:type].to_s).compact
    end
  end
end
