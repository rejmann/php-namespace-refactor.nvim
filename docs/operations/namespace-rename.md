# Namespace rename

**Files:** `lua/php-namespace-refactor/app/rename_feature.lua`, `app/operations/namespace_rename.lua`, `infra/composer.lua`

## Responsibility

Runs when the rename is triggered with the cursor on the `namespace Foo\Bar;` line and a new namespace is given.

## Flow

```
<Plug>(PhpNamespaceRefactorRename) / :PhpNamespaceRefactor rename / require(...).rename()
  → rename_feature.rename()
      cursor line → domain/rename.detect_type → 'namespace'
      vim.ui.input({ default = current namespace }), asked again while invalid
  → namespace_rename.execute(file, ns)   ← here
  → app/move.lua                         ← moves the file, then the file move operation
```

## What it does

1. Resolves the new namespace to its directory through PSR-4 (`composer.directory_from_namespace`, longest prefix first, see [autoload.md](../autoload.md)):

   ```
   App\Services\Auth  →  <root>/src/Services/Auth
   ```

2. Builds the new path with the same file name and extension:

   ```
   <root>/src/Domain/UserController.php  →  <root>/src/Services/Auth/UserController.php
   ```

3. Calls `move()`, which creates the directory, moves the file and runs the file move operation (see [file-move.md](./file-move.md)): namespace declaration, references and imports.

## Valid namespaces

`domain/rename.validate(ns, 'namespace')`: not empty, no leading, trailing or doubled `\`, starts with a letter, and every segment is a valid identifier (`Foo\Bar`).

## Error behavior

If no PSR-4 prefix covers the new namespace, nothing moves and `PhpNamespaceRefactor: no psr-4 mapping found for namespace …` is shown. Add a matching entry to `autoload` or `autoload-dev` in `composer.json`, or pick a namespace under an existing prefix.
