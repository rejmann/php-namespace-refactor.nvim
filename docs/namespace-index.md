# Namespace index

**Files:** `lua/php-namespace-refactor/infra/index.lua`, `infra/files.lua`

## Responsibility

To update every reference to a moved class without reading the whole project on each operation, each composer project gets an index of which classes every file imports. `app/services/multi_file_reference_updater.lua` asks it which files import the old fully qualified name (`Index:files_using()`).

The index is an optimization, not a source of truth: the reference updater always adds a scan of the project files for the old name's text, so a stale or broken index only makes a refactor slower, never incomplete.

## How it's built

On the first `FileType php` of a buffer inside a composer project (`plugin/php-namespace-refactor.lua` → `index.ensure_built()`), never at startup:

1. `index.get(root)` loads the saved index of that project, if any
2. `Index:build()` lists the project files (`infra/files.lua`: `rg`, then `git ls-files`, then a directory walk; honors `ignored_directories` and `additional_extensions`)
3. Files whose mtime differs from the saved entry are read and parsed (`index.parse()`): the declared `namespace` and the line-leading `use` imports (plain or aliased, leading `\` stripped). Unchanged files are skipped, files that no longer exist are dropped
4. Work runs in chunks of `CHUNK_SIZE` (200) files with `vim.schedule` in between, so the editor stays responsive on large projects
5. The result is saved

## How it's kept up to date

| Event | Where | Effect |
|---|---|---|
| `BufWritePost` | `index.on_write()` | Re-parses the written file and saves |
| A refactored move | `app/operations/file_move.lua` | Drops the old path, indexes the new one, saves |
| Explorer creates files | `infra/lsp.lua` (`workspace/didCreateFiles`) | Indexes the new files (also inside a created folder) |
| Explorer deletes files | `infra/lsp.lua` (`workspace/didDeleteFiles`) | Drops the files, or everything under a deleted folder |

There's no debounce: each event saves the index once.

## Where the cache is stored

One JSON file per project, named after the sha256 of the project root:

```
stdpath('cache')/php-namespace-refactor/<sha256(root)>.json
```

Usually `~/.cache/nvim/php-namespace-refactor/`. To find the file of a project:

```vim
:lua print(require('php-namespace-refactor.infra.index').get(vim.fs.root(0, 'composer.json')).path)
```

## Cache format

```json
{
  "version": 1,
  "root": "/path/to/project",
  "files": {
    "/path/to/project/src/Controller/UserController.php": {
      "declares": "App\\Controller",
      "imports": ["App\\Models\\User"],
      "mtime": "1761222000.123456789"
    }
  }
}
```

Only per-file entries are saved; the reverse map (FQCN → files) is rebuilt when the file is loaded. A file with another `version` is ignored and rebuilt.

## Inspecting or clearing the cache

```sh
jq . ~/.cache/nvim/php-namespace-refactor/<hash>.json   # inspect
rm -r ~/.cache/nvim/php-namespace-refactor              # clear every project
```

Clearing is always safe: the next PHP file opened in the project rebuilds the index. `:checkhealth php-namespace-refactor` shows how many files the current project's index holds.

## Signs something is wrong with the index

Since the reference updater always scans too, a broken index can't cause missed references, only slower refactors. If refactors get noticeably slow, clear the cache.
