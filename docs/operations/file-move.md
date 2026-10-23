# File move

**Files:** `lua/php-namespace-refactor/app/move.lua`, `app/operations/file_move.lua`, `app/services/*`

## Responsibility

Refactors the project after PHP files or directories moved. This is the convergence point of **every** flow:

- `:PhpNamespaceRefactor move` / `require('php-namespace-refactor').move()` (`app/move.lua`)
- the rename feature, which only computes a new path and calls `move()` (see [class-rename.md](./class-rename.md) and [namespace-rename.md](./namespace-rename.md))
- file explorers, through `workspace/didRenameFiles` on the in-process language server (`infra/lsp.lua`)

## Flow

```
app/move.lua (command/API)                      infra/lsp.lua (explorers)
  vim.uv.fs_rename, buffers follow                 the explorer already moved the file
          └──────────────┬──────────────────────────────┘
                         ↓
file_move.enqueue(moves)                     serial queue
  → file_move.execute(moves)
      → directory_moved_files_resolver       1. directories → one move per file
      → for each move with a configured extension on both sides:
          → namespace_batch_updater          2. class name, namespace declaration, references
          → missing_class_importer           3. (auto_import_namespace) import old siblings
          → import_remover                   4. (remove_unused_imports) drop same-namespace imports
          → index + file listing updated     5. keep the namespace index in sync
```

### Moving the file (`app/move.lua`)

Absolute paths; refuses a missing source, an existing destination or identical paths; creates the destination's parent directories; `vim.uv.fs_rename`. Then every loaded buffer of the file (or of anything under the directory) is pointed at its new path with `nvim_buf_set_name`. Unmodified buffers are written right away (`noautocmd write!`, same content) so Neovim considers them as editing the new file; otherwise the next `:write` fails with `E13`. The stale unlisted buffer left for the old name is deleted.

### Serial queue

`file_move.enqueue()` appends to a list and processes one batch per `vim.schedule` tick, never two at once, so renames reported in quick succession (several files dragged in an explorer) apply in order on a consistent state. A failure in a batch is reported and doesn't stop the queue.

## Step by step

### 1. Directory expansion (`app/services/directory_moved_files_resolver.lua`)

Explorers report a single `{ old, new }` pair for a whole directory. If `new` is a directory on disk, every file under it becomes a move, with its old path rebuilt from the relative path. If `new` isn't on disk but neither path has an extension, the loaded buffers under `new` are used instead. Otherwise it's a file move. Duplicates are dropped.

### 2. Namespace and references (`app/services/namespace_batch_updater.lua`)

1. Resolves the class's new and old fully qualified names from the paths (`composer.class_namespace`, both against the new path's project, since the old path no longer exists). A file outside every PSR-4 mapping stops here
2. If the class name changed, `class_name_updater` renames the declaration (and in-file references) to match the file name
3. `moved_file_namespace_updater` rewrites the name in the `namespace …;` declaration. A file without one stops here: there's nothing to propagate
4. `multi_file_reference_updater` updates the rest of the project

#### `multi_file_reference_updater`: finding affected files

The union of:

- **the index**: `Index:files_using(old_fqcn)`, see [namespace-index.md](../namespace-index.md)
- **a scan**: every project file (`infra/files.lua`) whose text on disk contains the old fully qualified name

So an empty or stale index never leaves references behind, it only makes the operation slower.

#### Edits per affected file

All computed against the file's text from `fs.read_text()` (buffer contents when loaded) and collected in one `WorkspaceEdit`:

- every old FQCN → new one. Only the right side is boundary-checked, so `\App\Domain\Order` matches while `App\Domain\OrderAbstract` and `App\Domain\Order\Line` don't
- when the class name changed, every whole-word occurrence of the old short name → new, skipping those inside an FQCN already being replaced (they would overlap)
- [property renaming](#property-renaming), when enabled
- when the file had no FQCN occurrence, sits in the class's old directory and uses the short name, and the class left that directory: a `use` for the new FQCN

Then the files in the class's **old directory** that weren't already affected get the short-name rename (if the class was renamed) and the `use` (if it moved away), and the renamed file itself gets the property check (self-typed properties, e.g. a linked-list node).

The `WorkspaceEdit` is applied once (see [architecture.md](../architecture.md#edits)); a file that can't be edited is reported and the others still are. Finally `import_remover` runs for the moved file.

#### Property renaming

Only when `rename_properties` is enabled and the class name changed (`property_rename.resolve_names`), only on the files above:

1. The expected property names come from the class names (`Test` → `test`, `NewTest` → `newTest`)
2. `domain/property/locator.lua` finds the single constructor parameter typed with the class, looking for the new class name if it's already in the text, otherwise the old one. Promoted or not, readonly or not, nullable, attributes ignored; a non-promoted one must be assigned with `$this->x = $x;`, and its class-body declaration is found even without a type hint (`@var`-only)
3. Two parameters of that type → the file is skipped rather than guessing
4. A property already named after the new class is left alone. One not named after the old class is only renamed with `rename_mismatched_names`
5. Renames `$old` in the constructor and the declaration, and `$this->old` everywhere in the file

### 3. Importing old siblings (`app/services/missing_class_importer.lua`)

With `auto_import_namespace`, when the class changed directory: the classes of the old directory (by file name) that the moved file uses by short name and doesn't import get a `use` with their FQCN.

### 4. Removing redundant imports (`app/services/import_remover.lua`)

With `remove_unused_imports` (checked inside the service): in the moved file, imports of its new siblings; in each sibling, the import of the moved class. Only non-aliased imports whose namespace **is** the file's namespace are removed. The VS Code version matched short names only, which could drop an import of a same-named class from another namespace, or an aliased import still in use.

### 5. Index

The old path is dropped from the index, the new one indexed, the index saved, and the project's file listing cache cleared.

## Error handling

Each move runs in a `pcall`: a failure is reported with `vim.notify` and the remaining moves still run. Edits already applied for that move are not rolled back.
