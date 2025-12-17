# Lucid Array Dart Generator

Backend Swagger changes, we spend half a day retyping models, and somebody still
misses a field. This package aims to solve that. This tool takes in the Swagger/OpenAPI file
and generates Dart models plus ready‑to‑use service clients that call the
`ApiService` interface. One command, everything stays in sync, no copy/pasting.

## What you get

- **DTOs + enums** – Null-safe models for every schema, wired up with
  `fromJson`/`toJson`.
- **Service clients** – Namespaced clients (`OrgService`, `UserService`, etc.)
  that call your `ApiService` using typed path/body/query params.
- **Shared helpers** – Tiny `service_helpers.dart` plus `services.dart` /
  `models.dart` barrels so you import one file per layer.
- **Namespaced output** – Each spec lands in `fooModels` + `fooService`, so
  multiple APIs live side-by-side.
- **Chill CLI** – `swagger_gen` works via `dart run` or `dart pub global run`
  with defaults that just make sense.

## Install it

### Drop it into dev_dependencies (Flutter apps)

```yaml
dev_dependencies:
  lucid_array_dart_generator: ^0.0.1
```

Then run `dart pub get`.

### Or install it globally

```sh
dart pub global activate lucid_array_dart_generator
```

Once activated you can run the CLI with
`dart pub global run lucid_array_dart_generator:swagger_gen …`.

## Quick start (copy/paste time)

```sh
dart run lucid_array_dart_generator:swagger_gen \
  https://api.example.com/org/docs/swagger.json \
  -o lib/services/generated \
  --api-service-path lib/services/api_service.dart
```

This creates:

```
lib/services/generated/
├── models/
│   └── orgModels/
│       ├── *.dart
│       └── models.dart
└── services/
    └── orgService/
        ├── *.dart
        ├── service_helpers.dart
        └── services.dart
```

### CLI flags worth knowing

| Option | Default | Description |
|--------|---------|-------------|
| `-o, --output` | `lib/services/generated` | Base directory for all generated files. |
| `-m, --models` | `models` | Subdirectory (inside `--output`) that houses model namespaces. |
| `-s, --services` | `services` | Subdirectory (inside `--output`) that houses service namespaces. |
| `--api-service-path` | `lib/services/api_service.dart` | Path the generated clients use when importing your `ApiService`. |
| `--base-path` | current directory | Working directory used for resolving relative paths. |
| `--schema_name` | _(inferred)_ | When set in `GeneratorOptions`, overrides the namespace used for `<namespace>Models` / `<namespace>Service`. |
| `--format` | `true` | Run `dart format` on every generated file. |
| `--overwrite` | `true` | Replace existing files (set to `false` to keep manual edits). |
| `--verbose` | `false` | Emit detailed log output. |

> Tip: the namespace defaults to the file/URL segment of your schema
> (`…/org/docs/swagger.json` → `orgModels`/`orgService`). Pass a custom
> `schema_name` in `GeneratorOptions` or set `-m`/`-s` if you want tighter
> control.

## What lands on disk

- **DTOs** live in `<output>/models/<namespace>Models/` with a `models.dart`
  barrel so you can `import '.../models.dart';` and be done.
- **Services** live in `<output>/services/<namespace>Service/`, one class per
  tag, with typed params and a shared helper for decoding responses.

- **ApiService contract**: The generator expects an `ApiService` with:
  `get`, `post`, `put`, `patch`, `delete` methods returning
  `Future<ApiResponse<T>>`. You can swap in your own implementation as long as
  the signature matches.

## Daily flow

1. Run the CLI with your spec (local file or URL).
2. Import the generated `models.dart` / `services.dart` barrels in your app.
3. Re-run whenever the Swagger doc changes. It’s idempotent, so drop it into CI,
   a melos task, or whatever build script you like.

## Heads-up / FAQ

- **Undefined class?** Import the barrel (`…/models/orgModels/models.dart`)
  instead of individual files.
- **Custom folders?** Pass `--models`, `--services`, or set `schema_name`.
- **Multiple specs?** Run the CLI per spec; each gets its own namespace.

## Contributing

Ideas welcome—open an issue with a sample schema if you want something like
multipart support, custom serializers, or build.yaml hooks. For local dev:

```
dart format lib test bin
flutter test
```

## License

This project is available under the MIT license. See [LICENSE](LICENSE) for
details.
