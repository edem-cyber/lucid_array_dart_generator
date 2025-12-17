# Lucid Array Dart Generator

Every time the backend swagger changes, we end up hand‑editing the same models
and service classes. This package solves that. Point it at a Swagger/OpenAPI
doc, hit run, and you instantly get the Dart DTOs plus strongly typed service
clients wired to your `ApiService`. No more copy/paste or “oops the schema
changed” bugs.

## What you get

- **DTOs + enums** – Null‑safe models for every schema, already wired up with
  `fromJson`/`toJson`.
- **Service clients** – Namespaced clients (`OrgService`, `UserService`, etc.)
  that call your `ApiService` using typed path/body/query parameters.
- **Shared helpers** – A tiny `service_helpers.dart` plus `services.dart` /
  `models.dart` entry points so you import one file per layer.
- **Namespaced output** – Each Swagger spec lands in `fooModels` +
  `fooService`, so multiple APIs can coexist without collisions.
- **Chill CLI** – `swagger_gen` works via `dart run` or `dart pub global run`
  with thoughtful defaults and verbose logging when you need it.

## Install

### As a dev dependency (recommended for Flutter apps)

```yaml
dev_dependencies:
  lucid_array_dart_generator: ^0.0.1
```

Then run `dart pub get`.

### As a globally activated tool

```sh
dart pub global activate lucid_array_dart_generator
```

Once activated you can run the CLI with
`dart pub global run lucid_array_dart_generator:swagger_gen …`.

## Quick start

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

## Generated layout

- **DTOs** live under `<output>/models/<Namespace>Models/`. Every schema becomes
  a class with:
  - required/optional constructor parameters and guarded `toJson` helpers.
  - enum helpers (`fromJson`, `.value`) and typed wrappers for order/filter DTOs.
  - `models.dart` barrel export so app code can `import '.../models.dart';`.

- **Service clients** live under `<output>/services/<Namespace>Service/` and:
  - mirror each tag/rest client from the spec (`OrganizationsService`,
    `PermissionsService`, etc.).
  - expose positional path parameters, typed named query arguments, and body
    parameters that call `yourDto.toJson()`.
  - include `service_helpers.dart` (`decodeJsonObject`, `decodeJsonList`) and a
    `services.dart` barrel.

- **ApiService contract**: The generator expects an `ApiService` with:
  `get`, `post`, `put`, `patch`, `delete` methods returning
  `Future<ApiResponse<T>>`. You can swap in your own implementation as long as
  the signature matches.

## Typical workflow

1. Point the CLI at your schema (local file or URL):

   ```sh
   dart run lucid_array_dart_generator:swagger_gen openapi/org.json \
     -o lib/services/generated \
     -m orgModels \
     -s orgService
   ```

2. Import the generated barrels where you need them:

   ```dart
   import 'package:my_app/services/generated/models/orgModels/models.dart';
   import 'package:my_app/services/generated/services/orgService/services.dart';

   final client = OrganizationsService();
   final response = await client.getOrganizations(
     queryOrganizationDto: QueryOrganizationDto(limit: 20),
   );
   ```

3. Rerun the command whenever the Swagger document changes. Regeneration is
   idempotent, so you can wire it into CI/CD or a `melos`/`make` script.

## Heads-up / FAQ

- **“Undefined class …”** – ensure you import the generated barrel
  (`…/models/<namespace>Models/models.dart`). The generator no longer emits
  per‑file imports from your application code.
- **Custom namespace/folder** – either set `--models` / `--services` or provide
  a `schema_name` in `GeneratorOptions`.
- **Multiple specs** – run the CLI per spec. Each run writes into a unique
  `<Namespace>Models` / `<Namespace>Service` folder so they can coexist.

## Contributing

New ideas welcome—open an issue with a sample schema if you spot a gap (multipart,
custom serializers, build.yaml hooks, etc). For local dev:

```
dart format lib test bin
flutter test
```

## License

This project is available under the MIT license. See [LICENSE](LICENSE) for
details.
