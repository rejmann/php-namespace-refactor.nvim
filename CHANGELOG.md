# Changelog

## [1.0.2](https://github.com/rejmann/php-namespace-refactor.nvim/compare/v1.0.1...v1.0.2) (2026-10-23)


### 📚 Documentation

* use grn in the rename mapping examples ([b4f8e9f](https://github.com/rejmann/php-namespace-refactor.nvim/commit/b4f8e9fecec0de9621f5ca1728f62dfe38e526af))
* use grn in the rename mapping examples ([90570c8](https://github.com/rejmann/php-namespace-refactor.nvim/commit/90570c8a576ba878e626c95bb3d121f474f535cd))

## [1.0.1](https://github.com/rejmann/php-namespace-refactor.nvim/compare/v1.0.0...v1.0.1) (2026-10-23)


### 📚 Documentation

* drop the F2 mapping suggestion ([5a9e6b3](https://github.com/rejmann/php-namespace-refactor.nvim/commit/5a9e6b3782d0656fbfdf47752d5f44d0c4ed4b9d))
* drop the F2 mapping suggestion ([c6d84c9](https://github.com/rejmann/php-namespace-refactor.nvim/commit/c6d84c9aa56312e9a6ce79caa38f54e42d607de8))
* wrap the rename mapping example in the vimdoc ([a079532](https://github.com/rejmann/php-namespace-refactor.nvim/commit/a079532919dde5f18add861c33cc40b50689108b))

## 1.0.0 (2026-10-23)


### ⚠ BREAKING CHANGES

* the repository no longer builds a VS Code extension; it is a Neovim plugin.

### 🚀 New Features

* add :PhpNamespaceRefactor move command ([cc47b44](https://github.com/rejmann/php-namespace-refactor.nvim/commit/cc47b443afa61bcbc323e0d5b37becb041d0ebcc))
* add health check ([0001fed](https://github.com/rejmann/php-namespace-refactor.nvim/commit/0001fed4b11400b2e1339b67efbfd1e15ff2ce46))
* add rename command and &lt;Plug&gt; mapping ([b87610b](https://github.com/rejmann/php-namespace-refactor.nvim/commit/b87610b44ffee439fbe5a392c374eb679c023b14))
* **app:** add file move operation with directory expansion ([dd7bf38](https://github.com/rejmann/php-namespace-refactor.nvim/commit/dd7bf38d0b9c556f873e8450f19010a7b8d8ec36))
* **app:** port import remover and missing class importer ([151d435](https://github.com/rejmann/php-namespace-refactor.nvim/commit/151d435a06952b785f1850572d32e4cb4c259a18))
* **app:** port multi-file reference updater ([15d92c4](https://github.com/rejmann/php-namespace-refactor.nvim/commit/15d92c438df2a5f3cb35838071ae6eebd95ae8e1))
* **app:** port property rename operation ([bf61f11](https://github.com/rejmann/php-namespace-refactor.nvim/commit/bf61f11ca864c7ae98ee3c0ce2296b0d0fc78c19))
* **app:** update namespace and class name of moved file ([175b18f](https://github.com/rejmann/php-namespace-refactor.nvim/commit/175b18fa8dc90d134bd831426ee4549a76cd997a))
* **config:** add config resolution and validation ([5e897d1](https://github.com/rejmann/php-namespace-refactor.nvim/commit/5e897d1361f38c904ad8990e4a45358cfa6f4d1c))
* **domain:** port path and extension resolution ([64ba28e](https://github.com/rejmann/php-namespace-refactor.nvim/commit/64ba28e27bdebec03c52dc0290bc784e70534acd))
* **domain:** port php patterns ([49552db](https://github.com/rejmann/php-namespace-refactor.nvim/commit/49552dbd1afb461b1665b5642786512cda6089f1))
* **domain:** port rename detection and validation ([82845bf](https://github.com/rejmann/php-namespace-refactor.nvim/commit/82845bf8eb8db936a38f3ac72396d28f66c7890f))
* **domain:** port typed property detection ([2b51a18](https://github.com/rejmann/php-namespace-refactor.nvim/commit/2b51a182e44af095b287f87c17ea0e8bb1f6f81d))
* **domain:** port use statement handling ([d33c86a](https://github.com/rejmann/php-namespace-refactor.nvim/commit/d33c86a6586e4f25fce9728a600768ff6ceab73f))
* **infra:** add persistent namespace index ([bce55c5](https://github.com/rejmann/php-namespace-refactor.nvim/commit/bce55c596424562087d817f332c89930201ec62b))
* **infra:** add text edit collector and applier ([d5ff993](https://github.com/rejmann/php-namespace-refactor.nvim/commit/d5ff9939bff404fb2e75763f02c353d4e82f1315))
* **infra:** add workspace file listing ([fe64eee](https://github.com/rejmann/php-namespace-refactor.nvim/commit/fe64eeeac4fae9f425f2bc9885009e79a6cda83a))
* **infra:** read composer psr-4 autoload ([8f90a69](https://github.com/rejmann/php-namespace-refactor.nvim/commit/8f90a6906fb1b7e2597627a6c813ca420af1d97d))
* **lsp:** add in-process lsp for explorer file operations ([a29f6e7](https://github.com/rejmann/php-namespace-refactor.nvim/commit/a29f6e7038be7f6b758e2a3e4415e06b6dd53519))


### 📚 Documentation

* add neovim migration plan ([7bb8dab](https://github.com/rejmann/php-namespace-refactor.nvim/commit/7bb8dabbe6bd0a1d6c1a262d650c0d1260461b2f))
* add vimdoc and rewrite readme for neovim ([49515e2](https://github.com/rejmann/php-namespace-refactor.nvim/commit/49515e2ee281fb459111510b59d395f0668e7148))
* link the original vscode extension repository ([3b82690](https://github.com/rejmann/php-namespace-refactor.nvim/commit/3b82690c376f95c058d296056e8666a08ec08dc4))
* sync ci notes in migration plan ([da76c27](https://github.com/rejmann/php-namespace-refactor.nvim/commit/da76c27510c26e37438a444c0577a743db1bab67))


### 🧪 Tests

* add busted + nlua harness ([a8715bd](https://github.com/rejmann/php-namespace-refactor.nvim/commit/a8715bdfef8b6fbc7e9d22c9c8befd54a9255694))


### 🔧 Chores

* remove vscode extension sources ([2b60eb8](https://github.com/rejmann/php-namespace-refactor.nvim/commit/2b60eb82199746162bc6a1d6c6bc6a511011b581))
* scaffold neovim plugin layout ([28a42c0](https://github.com/rejmann/php-namespace-refactor.nvim/commit/28a42c0937105e599fd030ed50870745654f5adc))
* start versioning the neovim plugin at 1.0.0 ([abc2e13](https://github.com/rejmann/php-namespace-refactor.nvim/commit/abc2e138f68c5ccf669de29dda92421b68e4f834))


### ⚙️ Continuous Integration

* add lint, typecheck and test workflow ([a255984](https://github.com/rejmann/php-namespace-refactor.nvim/commit/a2559846e797fcb5e89ed5cb13c2aaca258f0c56))
* install neovim from release tarball ([e0d2f26](https://github.com/rejmann/php-namespace-refactor.nvim/commit/e0d2f263f5dd191c38e972eb563d9177d77006aa))
* migrate release-please to v4 and document releases ([dd18ea2](https://github.com/rejmann/php-namespace-refactor.nvim/commit/dd18ea2b674444d8196f6bbef117d73720e40259))
* migrate release-please to v4 and document releases ([9c779f1](https://github.com/rejmann/php-namespace-refactor.nvim/commit/9c779f15ebe09079c08fcef723823b33cf965096))
* switch release-please to simple release type ([6c97609](https://github.com/rejmann/php-namespace-refactor.nvim/commit/6c97609f75926a2325f00da5036f735ecb8a9090))
* switch release-please to simple release type (migration 25/25) ([043b762](https://github.com/rejmann/php-namespace-refactor.nvim/commit/043b762254b2ba73611a665a412c3619095fef06))

## Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org) for commit guidelines.

Versions of the VS Code extension this plugin was ported from are in the [php-namespace-refactor changelog](https://github.com/rejmann/php-namespace-refactor/blob/main/CHANGELOG.md).
