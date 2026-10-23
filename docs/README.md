# Technical documentation

Documentation for developing and troubleshooting php-namespace-refactor.nvim. For installation, options and usage, see the [main README](../README.md) and `:help php-namespace-refactor`.

## Where to start

- **[Architecture](./architecture.md)**: module layers, entry points and the main flows. Start here if this is your first time reading the codebase.
- **[Configuration](./configuration.md)**: how options are resolved and which module reads each one.

## How each operation works

- **[File move](./operations/file-move.md)**: `:PhpNamespaceRefactor move` and file explorer renames, the convergence point of every flow
- **[Class rename](./operations/class-rename.md)**: rename on `class Foo` / `interface` / `trait` / `enum`
- **[Namespace rename](./operations/namespace-rename.md)**: rename on `namespace Foo\Bar;`

## Infrastructure

- **[Namespace index](./namespace-index.md)**: the per-project cache used to find references quickly, how it's built and kept up to date, and how to inspect or clear it
- **[PSR-4 autoload resolution](./autoload.md)**: how `composer.json` is read and mapped to namespaces and directories; the place to start when a namespace rename doesn't work

## History

- **[Migration plan](./migration-plan.md)**: how the VS Code extension was ported to Neovim, phase by phase
