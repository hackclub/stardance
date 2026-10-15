# stardance

<a href="https://stardance.hackclub.com/">
  <img src="stardance-logo-df399a7f.png" alt="Stardance Logo Banner" width="100%">
</a>

what's launching on the hack club spaceport :fire:

## Development

Follow the [CONTRIBUTING.md](CONTRIBUTING.md) guide to get started with development.

## production deployment

We deploy to Coolify using Docker. Both the web and worker services use the same `Dockerfile`.

### web service

Just run it-- the entrypoint should trigger

```sh
./bin/thrust ./bin/rails server
```

### worker service

In the worker resource's **General** tab, add this to **Custom Docker Options**:

```sh
--entrypoint "./bin/rails solid_queue:start"
```
