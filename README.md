# php-namespace-refactor.nvim 🇧🇷

Hi PHP Developers 👋!

A Neovim plugin that refactors namespaces and references when PHP files and directories move, or when classes and namespaces are renamed. It keeps PSR-4 projects consistent without leaving the editor.

> Ported from the Visual Studio Code extension [php-namespace-refactor](https://github.com/rejmann/php-namespace-refactor) (versioned separately; this plugin starts at 1.0.0). See [Coming from VS Code](#coming-from-vs-code).

## Features

### 🚀 Automatic namespace refactoring

Move a PHP file or a whole directory (with a command, or in your file explorer) and the plugin updates:

- the `namespace` declaration of each moved file (and its class name when the file was renamed),
- every reference across the project: `use` statements, fully qualified names (`\App\Foo\Bar`), and the short class name on a rename,
- imports: classes left behind in the old directory get a `use` for the class that moved away, the moved class imports the old siblings it still uses, and imports made redundant by the move are removed.

Namespaces come from the `psr-4` mappings (`autoload` and `autoload-dev`) of the closest `composer.json`, so several projects can be open at once.

### ✏️ Rename classes and namespaces

With the cursor on `namespace App\Foo;` or `class Bar`, rename it: a class rename renames its file, and a namespace rename moves the file to the namespace's PSR-4 directory. Either way the whole project follows.

### 🗂️ File explorer integration

Moving or renaming files in **neo-tree**, **oil**, **nvim-tree** or **snacks** triggers the same refactor. These explorers tell LSP clients about file operations, and the plugin listens through a tiny in-process language server (no external process).

### 🧩 Optional property renaming

When a class is renamed, the constructor property typed with it can follow: `private Test $test` becomes `private NewTest $newTest`, including its `$this->test` usages (`rename_properties`).

## Requirements

- Neovim **0.10+**
- A `composer.json` with a `psr-4` autoload mapping
- Optional: `rg` or `git`, for fast project file listing that honors `.gitignore`

## Installation

The plugin loads lazily on its own, so no lazy-loading setup is needed.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'rejmann/php-namespace-refactor.nvim', version = '*' }
```

Neovim's built-in `vim.pack` (0.12+):

```lua
vim.pack.add({
  { src = 'https://github.com/rejmann/php-namespace-refactor.nvim', version = vim.version.range('*') },
})
```

`version = '*'` follows the latest tagged release (`vX.Y.Z`, [semver](https://semver.org)); drop it to track `main`. Breaking changes only land in major versions, so `version = '1.*'` stays on 1.x.

## Usage

| What | How |
|---|---|
| Move the current file | `:PhpNamespaceRefactor move src/Domain/Sales/Order.php` |
| Move a file or directory | `:PhpNamespaceRefactor move src/Domain src/Sales/Domain` |
| Rename the class/namespace under the cursor | `<Plug>(PhpNamespaceRefactorRename)` or `:PhpNamespaceRefactor rename` |
| From Lua | `require('php-namespace-refactor').move(old, new)` / `.rename()` |
| Check the setup | `:checkhealth php-namespace-refactor` |

The plugin defines no mappings. Map `<Plug>(PhpNamespaceRefactorRename)` to the key you prefer in PHP buffers, e.g. `<leader>rn`:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'php',
  callback = function(args)
    vim.keymap.set('n', '<leader>rn', '<Plug>(PhpNamespaceRefactorRename)', { buffer = args.buf })
  end,
})
```

`grn` is Neovim's LSP rename (`vim.lsp.buf.rename()`), handled by your PHP language server (intelephense, phpactor, ...), not by this plugin: the file isn't renamed or moved to the new namespace's directory by it.

Full documentation: `:help php-namespace-refactor`.

## Configuration

No configuration or `setup()` call is required. These are the defaults:

```lua
vim.g.php_namespace_refactor = {
  -- Path fragments never scanned or edited (relative to the project root).
  -- /vendor/, /var/ and /cache/ are always ignored.
  ignored_directories = { '/vendor/', '/var/', '/cache/' },
  -- Import the classes of the old directory that a moved class uses.
  auto_import_namespace = true,
  -- Remove imports made redundant by a move (same namespace).
  remove_unused_imports = true,
  -- Extensions handled besides php, e.g. { 'php', 'class.php', 'enum.php' }.
  additional_extensions = { 'php' },
  -- Enable the rename feature.
  rename = true,
  -- Write files that aren't open straight to disk. When false, they are
  -- loaded into buffers and left unsaved for review.
  edit_files_in_background = true,
  -- Rename the constructor property typed with a renamed class.
  -- true, or { rename_mismatched_names = false } to only rename properties
  -- already named after the old class.
  rename_properties = false,
}
```

The same options can be passed to `require('php-namespace-refactor').setup({ ... })`, which is merged over `vim.g.php_namespace_refactor`. See `:help php-namespace-refactor-config` for details.

### Undo

Neovim has no multi-file undo. Every buffer touched by a refactor gets the whole change as a single undo step. Files written in the background can be restored with version control, or set `edit_files_in_background = false` to review everything before writing.

## Coming from VS Code

| VS Code setting | Neovim option |
|---|---|
| `phpNamespaceRefactor.ignoredDirectories` | `ignored_directories` |
| `phpNamespaceRefactor.autoImportNamespace` | `auto_import_namespace` |
| `phpNamespaceRefactor.removeUnusedImports` | `remove_unused_imports` |
| `phpNamespaceRefactor.additionalExtensions` | `additional_extensions` |
| `phpNamespaceRefactor.rename` | `rename` |
| `phpNamespaceRefactor.editFilesInBackground` | `edit_files_in_background` |
| `phpNamespaceRefactor.renameProperties` (`{ "renameMismatchedNames": false }`) | `rename_properties` (`{ rename_mismatched_names = false }`) |

Dragging files in the VS Code Explorer becomes a move in a supported file explorer (or `:PhpNamespaceRefactor move`), and the F2 rename becomes `<Plug>(PhpNamespaceRefactorRename)` (mapped to a key of your choice).

## Documentation

- `:help php-namespace-refactor`: user documentation
- [docs/](./docs/README.md): architecture and internals, for contributors and troubleshooting

## Development

```sh
make test-lua       # busted specs, run inside Neovim through nlua
make lint-lua       # selene
make typecheck-lua  # lua-language-server --check
make format-lua     # stylua
```

To try the plugin by hand on the fixture project (work on a copy, commands change files on disk):

```sh
cp -R spec/fixtures/project /tmp/project
nvim --clean -u spec/minimal_init.lua /tmp/project/src/Foo/Bar.php
```

### Releasing

The plugin is distributed straight from this repository: plugin managers install the `vX.Y.Z` git tags, so there is no package registry to publish to. Releases are automated by [release-please](https://github.com/googleapis/release-please):

1. Merge PRs into `main` with [Conventional Commits](https://www.conventionalcommits.org) messages (`feat:`, `fix:`, `feat!:` for breaking changes).
2. The `release-please` workflow keeps a `🤖 chore: release X.Y.Z [bot]` PR open with the next version (from the commit types), the `CHANGELOG.md` entry and the `version.txt` bump.
3. Merging that PR tags `vX.Y.Z` and publishes the GitHub release, which plugin managers pick up.

Setup for the workflow (once per repository):

- Settings → Actions → General → Workflow permissions: **Read and write permissions** and **Allow GitHub Actions to create and approve pull requests**.
- Optional: a `RELEASE_PAT` secret (fine-grained token with Contents and Pull requests write access) so that CI also runs on the release PR; without it the workflow uses `GITHUB_TOKEN`.

## Release notes

See [CHANGELOG.md](./CHANGELOG.md).

---

By PHP Developer for PHP Developers 🐘
