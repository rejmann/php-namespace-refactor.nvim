# Configuration

How options are resolved, and which module reads each one. Useful when investigating "the plugin isn't respecting option X": start with the module listed. User-facing descriptions are in `:help php-namespace-refactor-config`.

## Resolution (`lua/php-namespace-refactor/config.lua`)

`config.get()` returns the effective options, computed on every call (so changes apply to the next operation):

1. `config.defaults`
2. `vim.g.php_namespace_refactor` (a table)
3. options given to `setup()` (merged over each other across calls)

The merge is **shallow**: a list option replaces the default list instead of being merged index by index (`vim.tbl_deep_extend` would turn `{ '/build/' }` into `{ '/build/', '/var/', '/cache/' }`).

`config.validate()` checks types with `vim.validate` (positional form on 0.11+, table form on 0.10; the 0.10 table form reads a function validator's third item as the error message, hence the compat helper). `setup()` raises on invalid options; `get()` reports them with `vim.notify` and returns the defaults, so a bad `vim.g` value doesn't break every autocmd. `:checkhealth` reports invalid values and unknown keys.

| Option | Type | Default | Read by |
|---|---|---|---|
| `ignored_directories` | `string[]` | `{ '/vendor/', '/var/', '/cache/' }` | `infra/files.lua` (project file listing) |
| `auto_import_namespace` | `boolean` | `true` | `app/operations/file_move.lua` (whether to run `missing_class_importer`) |
| `remove_unused_imports` | `boolean` | `true` | `app/services/import_remover.lua` (returns early when off) |
| `additional_extensions` | `string[]` | `{ 'php' }` | `domain/path.lua` (`match_extension`), `infra/files.lua`, `infra/lsp.lua` (file operation globs) |
| `rename` | `boolean` | `true` | `app/rename_feature.lua` |
| `edit_files_in_background` | `boolean` | `true` | `infra/edit.lua` (`WorkspaceEdit:apply`) |
| `rename_properties` | `boolean \| { rename_mismatched_names?: boolean }` | `false` | `config.property_rename_settings()`, used by `app/services/multi_file_reference_updater.lua` |

## `edit_files_in_background`

Controls how files **not loaded in a buffer** are edited (`infra/edit.lua`):

- `true` (default): the new text is written to disk, no buffer is created
- `false`: the file is loaded into a listed buffer, edited and left unsaved

Loaded buffers are always edited in place and left unsaved.

## `ignored_directories`

Plain substring match (not a glob) against the file's path **relative to the project root**, with a leading `/` (`infra/files.lua`). The VS Code version matched the absolute path, so a project under `/var/www/...` had every file ignored. `/vendor/`, `/var/` and `/cache/` are always added; a configured list can only add more.

## `additional_extensions`

Normalized by `domain/path.normalize_extensions()`: trimmed, lowercased, leading dots stripped, deduplicated, `php` always first. `match_extension()` tries the longest extensions first, so `class.php` is never shadowed by `php`. Matching ignores case.

## `rename_properties`

Off by default, unlike the other flags, because it renames identifiers (constructor parameters, properties, `$this->x` usages), not just type hints. It only acts when the class name actually changed, and only on the files the reference updater already found referencing that exact class, so a same-named class in another namespace is never touched. The property edits go into the same `WorkspaceEdit` as the class-name replacement. See [file-move.md](./operations/file-move.md#property-renaming).

`config.get_polymorphic_flag()` / `config.property_rename_settings()` resolve the value:

```lua
rename_properties = false                                -- disabled (default)
rename_properties = true                                 -- enabled, mismatched names renamed too
rename_properties = {}                                   -- same as true
rename_properties = { rename_mismatched_names = false }  -- enabled, only properties named after the old class
```

Enabling the feature (`true` or any table) defaults every child flag to `true`; the table form only turns specific children off. An unknown key in the table is a validation error.

`rename_mismatched_names` decides what happens when the property isn't named after the old class (e.g. `private Test $service`): renamed to the new class's name when `true`, left alone when `false`.

The polymorphic shape comes from the VS Code version, whose settings schema couldn't have `renameProperties` be both a boolean and the parent of `renameProperties.renameMismatchedNames`. It was kept for a one-to-one migration of existing configurations.
