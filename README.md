# 🌟 Stardance

This repository hosts the Ruby on Rails app for Hack Club's Stardance Challenge, a free summer STEM event for teens to build anything they want and earn prizes. Learn more at [stardance.hackclub.com](https://stardance.hackclub.com).

**Note:** Stardance launches June 1 for teens aged 13–18. RSVP at [stardance.hackclub.com](https://stardance.hackclub.com)!

## Getting Started

You'll need Docker Compose, Ruby, and Rails to run Stardance. We strongly encourage using a Unix-based system (Linux or macOS). If you're on Windows, check out [GitHub Codespaces](https://github.com/codespaces)!

### Setting up a brand-new development environment

1. Clone this repo!
    ```sh
    git clone https://github.com/hackclub/stardance
    ```
    (this will already be done for you if you use *GitHub Codespaces!*)

2. Set up a PostgreSQL database.
    ```sh
    docker compose up -d db
    ```

3. Enter Rails via Docker Compose. Run all other commands within this container!
    ```sh
    docker compose run --service-ports web /bin/bash
    ```

4. Install all dependencies.
    ```sh
    bundle install
    ```

5. Set up your `.env` file by copying over `example.env`. You'll need to follow the instructions in said `.env` file!
    ```sh
    cp example.env .env
    ```

6. Create an app on Hack Club Auth (HCA) Staging. Go to https://hca.dinosaurbbq.org/developer/apps, and click the `app me up!` button.
    - redirect URI: `http://localhost:3000/oauth/callback`
    - select *ALL THE SCOPES!!!!*

    **You may get an error like `The requested scope is invalid, unknown, or malformed` when authenticating.** If this is the case:
    - copy the `&state=<...>` parameter of the failing URL.
    - go to your app on HCA, and `Right click > Copy Link` on `Test Auth` to the right of the redirect URI.
    - you should get a URL like this:
        ```
        https://hca.dinosaurbbq.org/oauth/authorize?client_id=c1b86a9f2073eec8e457ce3eb169afb9&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Foauth%2Fcallback&response_type=code&scope=openid+profile+email+name+slack_id+verification_status
        ```
    - append the `&state=<...>` parameter you copied in the first step to the URL
    - navigate to that URL, and go through the normal auth flow

    This is only an issue in development environments.

7. Generate Rails credentials.
    ```sh
    EDITOR="nano" bin/rails credentials:edit --environment=development
    ```

    **Note:** You may need to remove the existing encrypted credentials file: `rm config/credentials/development.yml.enc`

    <details>
    <summary>
        <b>⚠️ You might not be able to run <code>credentials:edit</code> from outside the Docker container because of build errors. If this is the case, click here.</b>
    </summary>

    `credentials:edit` might fail on your machine outside of the Docker container because some native gems can fail during local builds.

    The problem with this is that we have *no* visual editors in the Docker container. As such, you'll have to install one.

    ```sh
    # For Debian/Ubuntu:
    apt-get update && apt-get install -y nano

    # For Alpine:
    apk update && apk add nano

    # For CentOS:
    yum install nano
    ```

    After installing `nano`, you should be able to invoke `credentials:edit`.

    </details>
    </br>

    You'll see an editor with a `.yml` file open. Take a look at [`docs/example_dev_creds.yml`](/docs/example_dev_creds.yml) for examples of how this file should look like! You've already generated some of these for `.env` - make sure they're the same.

    If you're using `nano`, press <kbd>CTRL</kbd> + <kbd>S</kbd> to save, then <kbd>CTRL</kbd> + <kbd>X</kbd> to exit.

8. Run `bin/dev` to start the development server on port 3000, then visit `http://localhost:3000` in your browser!

### Starting the development environment back up again

1. Set up your PostgreSQL database.
    ```sh
    docker compose up -d db
    ```

2. Enter Rails via Docker Compose. Run all other commands within this container!
    ```sh
    docker compose run --service-ports web /bin/bash
    ```

3. Some dependencies might've changed from the last time you've worked on Stardance. Doesn't hurt to check!
    ```sh
    bundle install
    ```

4. Run `bin/dev` to start the development server on port 3000, then visit `http://localhost:3000` in your browser!

## No Docker?

If you’re not using Docker (weirdo...), you’ll need a local PostgreSQL database and the standard Rails setup instead.

1. Double check your `.env` file to make sure it points to your local database.
2. Set up the database.
   ```sh
   bin/rails db:prepare
   ```

3. Start the development server.
   ```sh
   bin/dev
   ```

## Useful Commands

Here's a couple useful commands you'll likely need at some point:

```sh
docker compose run web bin/rails db:migrate      # Migrate the database (please don't do this if you are hooked up to prod)
docker compose run web bin/rails bundle install  # Install Ruby gems for the app
docker compose run web bin/lint                  # Run project lint checks
```

## Troubleshooting

If you're getting a file not found error, and you're on Windows, try running the commands below. They'll switch line endings to LF (linux) ones:

```
git config --local core.autocrlf false
git rm --cached -r .   
git reset --hard
```

**Note:** This will reset all of your code!

## Production Deployment

We deploy to Coolify using Docker. Both the web and worker services use the same `Dockerfile`.

### Web Service

Just run it, and the entrypoint should trigger:
```sh
./bin/thrust ./bin/rails server
```

### Worker Service

In the worker resource's **General** tab, add the following to **Custom Docker Options**:
```sh
--entrypoint "./bin/rails solid_queue:start"
```