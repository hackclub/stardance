<div align="center">

<a href="https://stardance.hackclub.com/">
  <img src="./app/assets/images/landing/header/stardance-logo.png" alt="Stardance Logo Banner" width="100%">
</a>

### what's launching on the hack club spaceport 🔥

[![Hack Club](https://img.shields.io/badge/hack-club-EC3750?style=flat&logo=hackclub&logoColor=white)](https://hackclub.com/)
![Rails](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fhackclub%2Fstardance%2Fmain%2FGemfile.lock&search=%5E++++rails+%5C%28%28%5B%5E%29%5D%2B%29%5C%29&replace=%241&flags=m&label=Rails&logo=rubyonrails&logoColor=white&color=CC0000)
![GitHub repo size](https://img.shields.io/github/repo-size/hackclub/stardance)
[![CI](https://github.com/hackclub/stardance/actions/workflows/ci.yml/badge.svg)](https://github.com/hackclub/stardance/actions/workflows/ci.yml)

</div>

## What is Stardance?

**[Stardance](https://stardance.hackclub.com/)** is a free online summer program for teens 13–18. Build any technical project you want (websites, games, apps, hardware), log your hours, and earn real prizes: Raspberry Pis, 3D printers, even a laptop. No experience needed. Guides and a community of over 100,000 teens are there to help you get started.

It runs June 1 – October 31, with weekly drops, freebies, and AMAs with astronauts. Run by Hack Club, a nonprofit that’s shipped 60,000+ prizes to teen makers across 48 US states and 129 countries.

## Development

Follow the **[CONTRIBUTING.md](CONTRIBUTING.md)** guide to get started with development.

## Production Deployment

We deploy to Coolify using Docker. Both the web and worker services use the same `Dockerfile`.

### Web Service

Just run it: the entrypoint should trigger

```sh
./bin/thrust ./bin/rails server
```

### Worker Service

In the worker resource's **General** tab, add this to **Custom Docker Options**:

```sh
--entrypoint "./bin/rails solid_queue:start"
```
