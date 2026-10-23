# PSR-4 autoload resolution

**File:** `lua/php-namespace-refactor/infra/composer.lua`

## Responsibility

The whole plugin depends on the `psr-4` mappings of `composer.json` to turn a file path into a namespace, and a namespace into a directory.

## Project root: `composer.root(file)`

`vim.fs.root(file, 'composer.json')`: the closest directory above the file with a `composer.json`. Every operation works per project, so several projects can be open at once. A file outside any composer project is left alone by every feature.

## Reading `composer.json`: `composer.read(root)`

Collects the entries of `autoload["psr-4"]` and `autoload-dev["psr-4"]` as `{ prefix, directory, dev }`:

- prefixes lose their trailing `\` (`App\` → `App`)
- directories are relative to the root, without `./` or a trailing `/` (`./src/` → `src`, the root itself is `''`)
- a prefix mapped to several directories (`"App\\": ["src/", "lib/"]`) becomes one entry per directory
- the global namespace (`"": "src/"`) is supported

The entries are cached per root until `composer.json`'s mtime changes. A missing or malformed `composer.json`, or one without `psr-4`, gives no entries, silently. `:checkhealth php-namespace-refactor` reports it.

## Directory → namespace: `composer.namespace_from_directory(dir, autoload?)`

Picks the entry with the **longest directory** that contains `dir`, matching whole path segments (`src` doesn't match `srcfoo`); `autoload` wins over `autoload-dev` on ties. The namespace is the prefix plus the remaining path segments: with `App\` → `src/`, `src/Domain/Sales` gives `App\Domain\Sales`.

Returns `nil` when no entry contains the directory, and `''` for the global namespace.

## A file's class: `composer.class_namespace(file, autoload?)`

`{ namespace?, class_name, full_namespace }`, where the class name comes from the file name minus its configured extension (`domain/path.lua`). A file outside every mapping (or in the global namespace) gets `full_namespace = class_name` and no `namespace`.

## Namespace → directory: `composer.directory_from_namespace(ns, autoload)`

Used by the namespace rename to find where a file goes. Picks the entry with the **longest prefix** that the namespace starts with, on whole segments (`App` doesn't match `Application`), and rebuilds the path: with `App\` → `src/`, `App\Domain\Sales` gives `<root>/src/Domain/Sales`. Leading and trailing `\` in the typed namespace are ignored.

Returns `nil` when no prefix covers the namespace. The rename then reports `no psr-4 mapping found for namespace …`. This is the most common "namespace rename doesn't work" case: the new namespace has no matching entry in `autoload`/`autoload-dev`.

## Differences from the VS Code version

- **Most specific mapping wins in both directions.** VS Code took the first match in `composer.json` order for path → namespace (decoded Lua tables have no key order anyway).
- **Whole-segment matching** in both directions.
- **`autoload-dev` is used for path → namespace too.** VS Code's `NamespaceCreator` effectively only looked at `autoload`.
- Array directories and the global namespace work. VS Code threw on the first and produced a leading `\` for the second.

## Things to watch for when supporting users

- **No `composer.json` above the file, or no `psr-4` section**: nothing happens. Check `:checkhealth php-namespace-refactor` from a buffer of the project
- **The file is outside every psr-4 directory**: it has no namespace, so moving it changes nothing
- **Overlapping prefixes** (e.g. `App\` → `src/` and `App\Tests\` → `tests/`) are fine: the most specific one wins
