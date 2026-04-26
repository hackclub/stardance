# stardance

what's launching on the hack club spaceport :fire:

check out [CONTRIBUTING.md](./CONTRIBUTING.md) for a more detailed guide on how to get up and running with this repo!

## non-exhaustive list of setup steps

### docker

me and the homies love docker, and it makes it stupid simple, so its highly recommended to use docker to make your life easier.

1. clone it (duh)
2. you most likely want a database here, so you can run that with this:

   ```bash
   docker compose up -d db
   ```

3. now to start cookin, run this and it will boot up rails

   ```bash
   docker compose run --service-ports web /bin/bash
   ```

4. now to really turn on the stove, run this (wait a few seconds for stuff to load) and point your browser to `http://localhost:3000`

   ```bash
   bin/dev
   ```

5. pull out some instant ramen

**random commands you might need**

if you just need to run a command once (eg test migrations or whatever) here is how

```bash
docker compose run web bin/rails db:migrate # please dont do this if you are hooked up to prod
docker compose run web bin/rails bundle install
docker compose run web bin/lint
```

if its giving you a file not found error and you are on windows, try running these commands. They switch line endings to lf (linux) ones

This will reset all your code!

```
git config --local core.autocrlf false
git rm --cached -r .   
git reset --hard
```



## i hate docker

weirdo, but okay, you gotta figure out how to get postgres running yourself bucko

1. double check your `.env` file to make sure its pointed at your database
2. setup the db

   ```bash
   bin/rails db:prepare
   ```

3. start the dev server

   ```bash
   bin/dev
   ```

4. have a fire extinguisher at the ready

## production deployment

We deploy to Coolify using Docker. Both the web and worker services use the same `Dockerfile`.

### web service

Just run it-- the entrypoint should trigger
```
./bin/thrust ./bin/rails server
```

### worker service

In the worker resource's **General** tab, add this to **Custom Docker Options**:
```
--entrypoint "./bin/rails solid_queue:start"
```
