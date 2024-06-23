# Wayfarer

[![Build Status](https://drone.harton.dev/api/badges/james/wayfarer/status.svg?ref=refs/heads/main)](https://drone.harton.dev/james/wayfarer)
[![Hippocratic License HL3-FULL](https://img.shields.io/static/v1?label=Hippocratic%20License&message=HL3-FULL&labelColor=5e2751&color=bc8c3d)](https://firstdonoharm.dev/version/3/0/full.html)

Wayfarer is a runtime-configurable HTTP reverse proxy using
[Bandit](https://hex.pm/packages/bandit) and
[Mint](https://hex.pm/packages/mint).

## Status

Wayfarer is yet to handle it's first HTTP request. Please hold.

## Installation

Wayfarer is [available in Hex](https://hex.pm/packages/wayfarer), the package
can be installed by adding `wayfarer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wayfarer, "~> 0.4.1"}
  ]
end
```

Documentation for the latest release can be found on
[HexDocs](https://hexdocs.pm/wayfarer) and for the `main` branch on
[docs.harton.nz](https://docs.harton.nz/james/wayfarer).

## Github Mirror

This repository is mirrored [on Github](https://github.com/jimsynz/wayfarer)
from it's primary location [on my Forgejo instance](https://harton.dev/james/wayfarer).
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
