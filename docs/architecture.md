# Architecture

How the plugin is organized, to help you find the right place when investigating a bug or a support question.

## Layers

Everything lives under `lua/php-namespace-refactor/`, in three layers:

| Layer | Folder | Responsibility |
|---|---|---|
| `domain` | `domain/` | Pure rules over strings: PHP patterns, `use` statements, paths and extensions, typed properties, rename validation. No `vim.api`, no file access: functions take text and return values or text edits |
| `infra` | `infra/` | Integrations: `composer.json` (`composer.lua`), file access preferring loaded buffers (`fs.lua`), collecting and applying edits (`edit.lua`), project file listing (`files.lua`), the namespace index (`index.lua`), the in-process language server (`lsp.lua`) |
| `app` | `app/` | Orchestration: `services/` are reusable steps, `operations/` run a full refactor, `move.lua` and `rename_feature.lua` are the user-facing entry points |

Next to them:

- `init.lua`: public API (`setup`, `move`, `rename`) and the `:PhpNamespaceRefactor` subcommands
- `config.lua`: defaults, merging, validation, see [configuration.md](./configuration.md)
- `health.lua`: `:checkhealth php-namespace-refactor`

Dependencies are plain `require`s. Where a test needs to swap something, it's a parameter (e.g. `extensions` in `domain/path.lua`, `index` in the multi-file updater) or a `luassert` stub; there's no DI framework.

## Entry points (`plugin/php-namespace-refactor.lua`)

The plugin file is small and requires nothing at startup ([`:help lua-plugin-lazy`](https://neovim.io/doc/user/lua-plugin.html)):

1. `:PhpNamespaceRefactor {move|rename}`: dispatched by `init.lua`
2. `<Plug>(PhpNamespaceRefactorRename)`: calls `require('php-namespace-refactor').rename()`. There are no default mappings
3. `FileType php` autocmd: builds the project's [namespace index](./namespace-index.md) and starts the in-process language server for the project (`infra/lsp.lua`), the first time a PHP file of a composer project is opened
4. `BufWritePost` autocmd: re-indexes the written file

## Main flows

```
:PhpNamespaceRefactor move {old} {new}       require('php-namespace-refactor').move()
  → app/move.lua: vim.uv.fs_rename, buffers follow the file
  → file_move.enqueue()                       see docs/operations/file-move.md

<Plug>(PhpNamespaceRefactorRename) / :PhpNamespaceRefactor rename
  → app/rename_feature.lua: detect namespace/class on the cursor line, vim.ui.input
  → operations/namespace_rename.lua or operations/class_rename.lua: compute the new path
  → app/move.lua                              (same as above)
  See docs/operations/namespace-rename.md and docs/operations/class-rename.md

File explorer moves or renames a file/directory (neo-tree, oil, nvim-tree, snacks)
  → workspace/didRenameFiles to the in-process language server (infra/lsp.lua)
  → file_move.enqueue()                       (same as above)
```

In other words, **every** refactor goes through `app/operations/file_move.lua`. The rename flows only decide the file's new path, and explorers already moved the file themselves.

## Edits

Services never write files directly. They compute `TextEdit`s (`{ start, finish, text }`, 0-based end-exclusive byte offsets into the text returned by `fs.read_text()`), collect them in an `infra/edit.lua` `WorkspaceEdit` and apply it once:

- a file loaded in a buffer is edited in place with a single `nvim_buf_set_text()` over the changed span (one undo step per buffer), and left unsaved
- other files are written to disk, or loaded into unsaved buffers when `edit_files_in_background` is off

Since edits are offsets into the text as it was read, every edit of one file in one `WorkspaceEdit` must be computed from that same text; overlapping edits are rejected.

## Other documents

- [Configuration](./configuration.md)
- [Namespace index](./namespace-index.md)
- [PSR-4 autoload resolution](./autoload.md)
