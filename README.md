# Wayfarer

[![Build Status](https://drone.harton.nz/api/badges/james/wayfarer/status.svg?ref=refs/heads/main)](https://drone.harton.nz/james/wayfarer)
[![Hippocratic License HL3-FULL](https://img.shields.io/static/v1?label=Hippocratic%20License&message=HL3-FULL&labelColor=5e2751&color=bc8c3d)](https://firstdonoharm.dev/version/3/0/full.html)

Wayfarer is a runtime-configurable HTTP reverse proxy using
[Bandit](https://hex.pm/packages/bandit) and
[Mint](https://hex.pm/packages/mint).

## Status

Wayfarer is yet to handle it's first HTTP request. Please hold.

## Installation

Wayfarer is not yet available on Hex, so you will need to add it as a Git
dependency in your app:

```elixir
def deps do
  [
    {:wayfarer, git: "https://harton.dev/james/wayfarer.git", tag: "v0.1.0"}
  ]
end
```

Documentation for `main` is always available on [my docs site](https://docs.harton.nz/james/wayfarer/Wayfarer.html).

## Github Mirror

This repository is mirrored [on Github](https://github.com/jimsynz/angle)
from it's primary location [on my Forejo instance](https://harton.dev/james/angle).
Feel free to raise issues and open PRs on Github.

## License

This software is licensed under the terms of the
[HL3-FULL](https://firstdonoharm.dev), see the `LICENSE.md` file included with
this package for the terms.

This license actively proscribes this software being used by and for some
industries, countries and activities. If your usage of this software doesn't
comply with the terms of this license, then [contact me](mailto:james@harton.nz)
with the details of your use-case to organise the purchase of a license - the
cost of which may include a donation to a suitable charity or NGO.
