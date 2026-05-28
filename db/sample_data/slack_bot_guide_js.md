# Make your own Slack bot by using JS!

## Introduction

Ever wanted to have your own Slack bot which responds to your commands, automates your tasks, and other stuff in Hack Club? In this guide, you will learn how to:

* Create a Slack app
* Build a Slack bot using JavaScript
* Add slash commands such as `/ping`
* Deploy your bot in [Hack Club Nest](https://nest.hackclub.com) for free
* Keep your bot online 24/7

This guide assumes no JavaScript experience. If you want a short intro to JavaScript first, read MDN's friendly overview: [MDN JavaScript Introduction](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Introduction)

The stack we'll use:

* JavaScript (no prior coding required)
* Node.js
* Slack Bolt
* Socket Mode
* Nest @ Hack Club

By the end of this tutorial you'll have your own fully hosted Slack bot.

---

## What you'll need

Before you start, gather these things:

* A Hack Club Slack account
* A GitHub account (for publishing your code)
* A Hack Club Nest account (used for hosting — see notes below about applying)
* Node.js and npm installed locally
* A code editor — VS Code is recommended

:::callout type="info"
**New to JS?** This [MDN intro](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Introduction) is a good quick primer.

**What's Nest?** Nest is a free Debian server Hack Club provides to students for hosting projects. Sign up via the [Hack Club Dashboard](https://dashboard.hackclub.app). Nest sometimes requires an application step — don't let the wait discourage you. If you already have an HCA (Hack Club Auth) account set up, the process is usually quick :)
:::

### What we're building

A Slack bot that responds to slash commands. A slash command is a command you type starting with a slash — for example:

```txt
/dsb-ping
/dsb-hello
/dsb-status
```

When a user runs one of these commands, the bot can show information, send messages, run automations, hit APIs, run workflows, and more. If you make a command like `/dsb-joke`, you can have the bot fetch a joke from an API and send it in the channel.

---

## Set up your Slack app

Before you can write any code, you need to register your bot with Slack and grab the tokens it'll use to authenticate.

### 1. Create the app

1. Go to the Slack Apps dashboard: [https://api.slack.com/apps](https://api.slack.com/apps) and click **Create New App → From scratch**.
2. Give it a name and pick the Hack Club workspace.
3. Click **Create App**.

### 2. Enable Socket Mode

Socket Mode lets your bot talk to Slack over a WebSocket so you don't need a public URL.

1. Open the **Socket Mode** page in your app's left sidebar.
2. Toggle **Enable Socket Mode** on.

![Image](https://cdn.hackclub.com/019e4e36-5cef-7730-8be8-f54a2a47abbe/image.png)

Socket Mode needs an *App-Level Token* with the `connections:write` scope:

1. Open **Basic Information** in the left sidebar.
   ![Image](https://cdn.hackclub.com/019e4e38-33ce-7846-8297-9e673a78e80a/image.png)
2. Scroll to **App-Level Tokens** and click **Generate Token and Scopes**.
   ![Image](https://cdn.hackclub.com/019e4e58-6018-7879-a809-11e783023b46/image.png)
3. Give the token a name (e.g. `my-bot-socket`) and add the `connections:write` scope.
   ![Image](https://cdn.hackclub.com/019e4e5a-5f07-71d8-9a9d-414521d23add/image.png)
4. Click **Generate** and copy the token immediately. App-level tokens start with `xapp-`.
   ![Image](https://cdn.hackclub.com/019e4e71-4726-7aff-a486-4620b141a10c/Screenshot%202026-05-22%20121630.png)

:::callout type="warning"
Slack has two token types — keep them straight:

* **Bot User OAuth Token** (starts with `xoxb-`) — used by your bot to perform actions like sending messages.
* **App-Level Token** (starts with `xapp-`) — used for Socket Mode and other app-level functionality.

Treat both like passwords. Don't share them, don't commit them to GitHub.
:::

### 3. Set bot scopes

Scopes tell Slack what your bot is allowed to do.

1. Open **OAuth & Permissions** in the left sidebar.
   ![Image](https://cdn.hackclub.com/019e4e6a-853f-7557-abda-c1257a44dc1d/image.png)
2. Under **Bot Token Scopes**, add:
   ![Image](https://cdn.hackclub.com/019e4e6c-dfde-7481-bb86-ab033e26b950/image.png)

   ```txt
   chat:write
   commands
   app_mentions:read
   channels:history
   ```

   These permissions let your bot send messages, use slash commands, read mentions, and access channel messages. You can always add more later.

### 4. Install the app to your workspace

1. Go to **Install App** in the left sidebar and click **Install to Workspace**.
2. Grant permissions.
   ![Image](https://cdn.hackclub.com/019e4e75-1181-7a8b-be19-fc0b36c92ca6/image.png)
3. Back on **OAuth & Permissions**, you'll see the **Bot User OAuth Token** (starts with `xoxb-`). Copy and save it.
   ![Image](https://cdn.hackclub.com/019e4e7c-cbc7-7b84-b607-ec62d2f7bacf/image.png)

### 5. Add a slash command

1. Open **Slash Commands** in the left sidebar and click **Create New Command**.
   ![Image](https://cdn.hackclub.com/019e4e7d-f648-74bc-bbaa-15cea4f1ebb1/image.png)
2. Enter a command name like `/dsb-ping` and provide a short description and usage hint.
3. Click **Save**.

:::callout type="info"
**Why `/dsb-` and not just `/ping`?** The Hack Club Slack workspace has many bots installed, and generic command names like `/ping` collide with other bots. Prefix yours with a short tag of your bot's name (here `dsb` for "Demo Slack Bot") so commands look like `/dsb-ping`, `/dsb-hello`, etc.

Keep a note of the *exact* command name — it's case-sensitive and you'll reference it in your code.
:::

### Where to find tokens later

If you lose a token, you can always go back:

* **App-Level Token (`xapp-`)** — **Basic Information** → **App-Level Tokens** → click the token name.
* **Bot User OAuth Token (`xoxb-`)** — **OAuth & Permissions** → look for **Bot User OAuth Token** after installing the app.

---

## Build the bot locally

Now we'll create the Node project, drop in the bot code, and run it on your machine.

### 1. Create the project

1. Create a new folder for your project and open it in VS Code.
2. Open the integrated terminal with **Terminal → New Terminal** so commands run inside the project folder.
3. Initialize the project and install dependencies:

   ```bash
   npm init -y
   npm install @slack/bolt dotenv
   ```

:::callout type="info"
**`npm: command not found` / `npm is not recognized`?** You don't have Node.js installed. Download it from [nodejs.org/en/download](https://nodejs.org/en/download), then re-run the commands above.
:::

:::callout type="warning"
Run all commands with the project folder as your terminal's working directory. If your terminal is sitting somewhere else, `npm install` will create files in the wrong place.
:::

### 2. Store your tokens in `.env`

Create a `.env` file in the project folder and paste your two tokens:

```env
SLACK_BOT_TOKEN=xoxb-...   # Bot User OAuth Token (from OAuth & Permissions)
SLACK_APP_TOKEN=xapp-...   # App-Level Token (from Basic Information → App-Level Tokens)
```

Then create a `.gitignore` so `.env` never gets committed:

```gitignore
node_modules
.env
```

:::callout type="info"
**Why a `.env` file?** It keeps secrets out of your code, which means you can push your repo to GitHub without leaking tokens. Always add `.env` to `.gitignore`.
:::

### 3. Write the bot

Create `index.js` in the project folder and paste this:

```js
require("dotenv").config();

const { App } = require("@slack/bolt");

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  appToken: process.env.SLACK_APP_TOKEN,
  socketMode: true
});

app.command("/dsb-ping", async ({ command, ack, respond }) => {
  const start = Date.now();
  await ack();
  const latency = Date.now() - start;
  await respond({ text: `Pong!\nLatency: ${latency}ms` });
});

(async () => {
  await app.start();
  console.log("bot is running!");
})();
```

:::callout type="warning"
If you used a different slash command name in the Slack dashboard, change `/dsb-ping` here to match.
:::

### 4. Run the bot

```bash
node index.js
```

If it works, you'll see:

```txt
bot is running!
```

Test your slash command in Slack — type `/dsb-ping` in any channel. The bot should reply with the latency.

![image](https://cdn.hackclub.com/019e4e05-aef2-7b7c-8064-8599e2b8b368/image.png)

:::callout type="tip"
**Nothing happens when you run the command?**

* Make sure your terminal is in the project folder (the one containing `index.js`).
* Double-check you copied the right token into the right variable. `xoxb-` goes in `SLACK_BOT_TOKEN`; `xapp-` goes in `SLACK_APP_TOKEN`.
* Watch the terminal where `node index.js` is running for errors.
:::

### How the command code works

```js
app.command("/command-name", async ({ ack, respond }) => {
  // your code here
});
```

| Part              | What it does                             |
| ----------------- | ---------------------------------------- |
| `app.command()`   | Registers a slash command                |
| `"/command-name"` | The command Slack listens for            |
| `async`           | Allows asynchronous operations like API calls |
| `ack()`           | Acknowledges the command to Slack        |
| `respond()`       | Sends a message back to Slack            |

:::callout type="warning"
`ack()` is required, and it needs to run within ~3 seconds. If you don't acknowledge in time, Slack thinks the command failed and shows the user an error.
:::

---

## Add more commands

Your bot is up. Now let's extend it with a help command and a couple of API-backed commands.

### Help command

```js
app.command("/dsb-help", async ({ ack, respond }) => {
  await ack();
  await respond({
    text:
`Available Commands:
/dsb-ping - Check bot latency
/dsb-catfact - Get a cat fact`
  });
});
```

![Example](https://cdn.hackclub.com/019e4e08-044a-7577-995f-e135b03ca9a3/image.png)

### Cat fact command (using an API)

To make API requests, install `axios`:

```bash
npm install axios
```

At the top of `index.js`, add:

```js
const axios = require("axios");
```

Then add this command:

```js
app.command("/dsb-catfact", async ({ ack, respond }) => {
  await ack();

  try {
    const response = await axios.get("https://catfact.ninja/fact");
    await respond({ text: `Cat Fact:\n${response.data.fact}` });
  } catch (err) {
    await respond({ text: "Failed to fetch a cat fact." });
  }
});
```

![Example](https://cdn.hackclub.com/019e4e0a-7a33-7c16-9c38-53e620ff89af/image.png)

### Joke command (one more example)

```js
app.command("/dsb-joke", async ({ ack, respond }) => {
  await ack();

  try {
    const response = await axios.get("https://official-joke-api.appspot.com/random_joke");
    await respond({
      text:
`${response.data.setup}

${response.data.punchline}`
    });
  } catch (err) {
    await respond({ text: "Failed to fetch a joke." });
  }
});
```

### How API commands work

Both the cat fact and joke commands follow the same flow:

1. User runs a slash command
2. The bot receives the command
3. The bot sends a request to an API
4. The API returns data
5. The bot sends that data back into Slack

The common ingredients:

* `axios` — to make API requests
* `try/catch` — to prevent crashes if the API fails
* `respond()` — to send messages back to Slack

You can repeat this pattern for as many commands as you want. Just remember to register each command in the Slack dashboard too. Browse [free-apis.github.io](https://free-apis.github.io/#/browse) for free APIs to play with.

:::callout type="info"
**API gotchas:**

* APIs have rate limits — always use `try/catch` so a failed request doesn't crash your bot.
* Some APIs require authentication — put their API keys in `.env`, never in your code.
:::

---

## Push to GitHub

Before deploying, get your code into a GitHub repository.

1. Create a new (empty) repository on GitHub.
2. In your project folder, run:

   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
   git push -u origin main
   ```

:::callout type="warning"
Double-check your `.gitignore` includes `.env` before you push. You can verify the file is being ignored by running `git status` — `.env` shouldn't appear.
:::

---

## Run it 24/7 on Nest

Right now your bot stops the moment you close your terminal. To keep it online 24/7, we'll deploy it to [Nest](https://nest.hackclub.com) and run it as a systemd service.

### 1. SSH into Nest

1. Make sure you have a Nest account (see the [Nest Quickstart Guide](https://guides.hackclub.app/index.php/Quickstart) if you're unsure how to log in).
2. SSH into your Nest server with your credentials.

### 2. Clone your repo

Once you're logged in, run:

```bash
git clone https://github.com/<your-github-username>/<your-repo-name>
cd <your-repo-name>
npm install
```

:::callout type="info"
**`git: command not found`?** Install it:

```bash
apt update && apt upgrade -y
apt install sudo -y
sudo apt install git -y
```
:::

### 3. Recreate the `.env` on the server

Your `.env` isn't in the repo (we gitignored it), so you need to create it on Nest:

```bash
nano .env
```

Paste in the same `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN` you had locally. To save and exit in nano: press `Ctrl+O`, then `Enter`, then `Ctrl+X`.

Test it runs:

```bash
node index.js
```

Try a slash command in Slack. If the bot responds, kill the process (`Ctrl+C`) — we'll set it up to run on its own next.

### 4. Run as a systemd service

Without systemd, your bot stops when you disconnect SSH, when Nest restarts, or when the process crashes. systemd keeps it alive.

1. Move into the systemd user directory:

   ```bash
   cd ~/.config/systemd/user
   ```

2. Create a service file:

   ```bash
   nano slackbot.service
   ```

3. Paste this in (edit the `WorkingDirectory` to match your Nest username and repo name):

   ```ini
   [Unit]
   Description=Slack Bot
   DefaultDependencies=no
   After=network-online.target

   [Service]
   Type=simple
   Restart=always
   WorkingDirectory=/home/<YOUR-NEST-USERNAME>/<YOUR-REPO-NAME>
   ExecStart=/usr/bin/node index.js
   TimeoutStartSec=0

   [Install]
   WantedBy=default.target
   ```

   Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Start it:

   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now slackbot.service
   ```

Congratulations — your bot is now running 24/7!

---

## Troubleshooting & next steps

### Checking logs

If anything misbehaves on Nest, check the systemd logs:

```bash
journalctl --user -u slackbot.service
```

### Common deployment issues

* **Wrong token** — confirm `xoxb-` is in `SLACK_BOT_TOKEN` and `xapp-` is in `SLACK_APP_TOKEN`.
* **Missing `.env`** — the file lives on the server now, not in your repo.
* **Wrong working directory** — the `WorkingDirectory=` line in `slackbot.service` must point to the absolute path of your project on Nest.
* **Missing dependencies** — re-run `npm install` inside the project folder on Nest.

### Lifecycle commands

Control the running bot from the Nest shell:

```bash
systemctl --user start slackbot.service     # start
systemctl --user stop slackbot.service      # stop
systemctl --user restart slackbot.service   # restart
```

### Further reading

* [Slack Docs](https://docs.slack.dev)
* [Slack Bolt JS Tutorial](https://slack.dev/bolt-js/tutorial/getting-started)
* [Node.js Docs](https://nodejs.org/)
* [Nest Quickstart Guide](https://guides.hackclub.app/index.php/Quickstart)

### Ideas to extend your bot

* Daily standup reporter (posts a summary at 9am)
* Fun facts bot (`/dsb-fact`)
* Moderation: auto-flag messages with banned words
* Games: trivia bot with score tracking
* Integrations: post GitHub PR updates
