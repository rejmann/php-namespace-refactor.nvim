# Class rename

**Files:** `lua/php-namespace-refactor/app/rename_feature.lua`, `app/operations/class_rename.lua`, `domain/rename.lua`

## Responsibility

Runs when the rename is triggered with the cursor on a class, interface, trait or enum declaration (`class Foo`, `final class Foo`, `enum Status: string`, ...) and a new name is given.

## Flow

```
<Plug>(PhpNamespaceRefactorRename) / :PhpNamespaceRefactor rename / require(...).rename()
  → rename_feature.rename()
      checks the rename option, a PHP buffer, and the cursor line (domain/rename.detect_type → 'class')
      vim.ui.input({ default = current name }), asked again with the error while invalid (domain/rename.validate)
  → class_rename.execute(file, name)    ← here
  → app/move.lua                        ← renames the file, then the file move operation
```

## What it does

Builds the new path, keeping the directory and the **full configured extension**:

```
/src/Domain/OldClass.php        →  /src/Domain/NewClass.php
/src/Domain/Color.class.php     →  /src/Domain/Shade.class.php   (with 'class.php' in additional_extensions)
```

Then calls `move()`, and the file move operation (see [file-move.md](./file-move.md)):

- renames the declaration inside the file (`class_name_updater`)
- updates every reference in the project: FQCNs, `use` statements, the short class name
- optionally renames the constructor property typed with the class (`rename_properties`)

## Valid names

`domain/rename.validate(name, 'class')`: not empty, doesn't start with a digit, no hyphens or spaces, only letters, digits and underscores, starting with a letter or underscore.

## Same result from a file explorer

Renaming `OldClass.php` to `NewClass.php` in neo-tree, oil, nvim-tree or snacks lands directly in the file move operation (through `workspace/didRenameFiles`), with the same result. The rename feature only adds the prompt and the path computation.
