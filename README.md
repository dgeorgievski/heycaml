# heycaml

Practice OCaml REST API application exposing simple health and version endpoints with configurable runtime settings.

## Features
- `GET /version` returns the application name and semantic version.
- `GET /healthz` (and the typo-friendly alias `/heatlhz`) reports the application status using the configured name as the JSON key.
- Configuration via defaults, JSON/YAML file, and command-line overrides (flag order of precedence).
- Structured request logging to stdout including timestamp, method, path, and status code.

## Prerequisites
- OCaml 4.14 (or newer) and [dune](https://dune.build/).
- Recommended workflow uses [opam](https://opam.ocaml.org/) for package management.

Install the required libraries once:

```bash
opam install dune opium yojson
```

## Build

```bash
dune build
```

## Run

```bash
# Default configuration: name=heycaml, port=8080
dune exec heycaml

# With an explicit configuration file and overrides
dune exec heycaml -- -config config/app.yaml -port 9090 -name my-api
```

### Command-line arguments
- `-config <path>`: JSON or YAML file providing configuration values.
- `-name <string>`: Overrides the application name.
- `-port <int>`: Overrides the HTTP port (1-65535).

Command-line flags take precedence over configuration file values, and both override built-in defaults.

### Configuration file examples

`config/app.json`

```json
{
  "name": "heycaml",
  "port": 8080
}
```

`config/app.yaml`

```yaml
name: heycaml
port: 8080
```

> The YAML loader accepts simple `key: value` pairs (strings or integers). For more advanced configuration needs, prefer JSON.

## API reference
- `GET /version` → `{ "name": "heycaml", "version": "1.0.0" }`
- `GET /healthz` → `{ "heycaml": "OK" }`
- `GET /heatlhz` → same as `/healthz` (added to mirror the specification typo).

## Logging
Every request is logged to stdout in the form:

```
2025-01-01T12:00:00Z GET /version -> 200
```

This includes an ISO-8601 UTC timestamp, the HTTP method, request path, and response status code.
