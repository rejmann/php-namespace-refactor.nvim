# Plano: migração php-namespace-refactor (VS Code → Neovim)

## Contexto

O repositório (já chamado `php-namespace-refactor.nvim`) contém hoje uma extensão VS Code em TypeScript (~2.6k LOC, camadas `app/domain/infra`, DI com tsyringe) que refatora namespaces PHP (PSR-4) ao mover/renomear arquivos e classes. O objetivo é portar todo o comportamento para um plugin Neovim em Lua, seguindo `:help lua-plugin` (guia oficial do Nvim 0.12, lido do runtime local), com commits pequenos por fase.

Decisões tomadas com o usuário:
- **TS removido só na última fase** (serve de referência durante o port).
- **Neovim mínimo 0.10** (`vim.uv`, `vim.fs.root`, `vim.system`, `vim.validate`).
- **Integração com explorers via LSP in-process** (`workspace/didRenameFiles` etc. — neo-tree, oil, nvim-tree e snacks já notificam todo cliente LSP).
- **Testes com busted + nlua** (padrão nvim-neorocks).

Este arquivo é a fonte de verdade do progresso: cada fase concluída vira um commit na branch `feat/neovim-migration`.

## Padrões do Neovim que o plano segue (`:help lua-plugin`)

- `plugin/php-namespace-refactor.lua` **pequeno**: só cria `:PhpNamespaceRefactor`, `<Plug>` maps e autocmds; todo `require()` fica dentro dos callbacks (lazy-loading implícito). Guard `vim.g.loaded_php_namespace_refactor`.
- **Configuração separada da inicialização**: funciona sem `setup()`. Config lida de `vim.g.php_namespace_refactor` (tabela) e `require('php-namespace-refactor').setup(opts)` apenas faz merge; validação com `vim.validate`.
- **Sem keymaps padrão**: expõe `<Plug>(PhpNamespaceRefactorRename)` + função Lua; README mostra como mapear `<F2>` em `ftplugin`/autocmd `FileType php`.
- **LuaCATS** (`---@class`, `---@param`) em tudo + `.luarc.json` + typecheck no CI (lua-typecheck-action).
- **`:checkhealth php-namespace-refactor`** via `lua/php-namespace-refactor/health.lua`.
- **vimdoc** em `doc/php-namespace-refactor.txt`; SemVer com release-please.
- Estilo Lua: `stylua` (2 espaços, aspas simples), `snake_case`, módulos retornando tabela `M`, `local` em tudo.

## Arquitetura alvo

```
plugin/php-namespace-refactor.lua        -- comandos, <Plug>, autocmds (sem require eager)
lua/php-namespace-refactor/
  init.lua            -- API pública: setup(), rename(), move(old, new)
  config.lua          -- defaults, merge vim.g + setup, validate, flag polimórfica
  health.lua
  domain/             -- regras puras, sem vim.api (testáveis isoladamente)
    php/patterns.lua        (PhpPatterns + ClassNameBoundaryRegexBuilder)
    php/use_statement.lua   (Locator, Creator, Injector → gera TextEdits)
    php/unused_imports.lua
    path.lua                (WorkspacePathResolver + FileExtensionResolver)
    property/*.lua          (ConstructorSpanFinder, ClassTypedPropertyLocator, ...)
    rename/*.lua            (ExtractNameFromCursor, TypeDetector, Validator)
  infra/
    composer.lua            (ComposerAutoloadManager + AutoloadPathResolver + Mapper)
    fs.lua                  (ler texto: buffer carregado > disco; listar arquivos)
    edit.lua                (WorkspaceEdit equivalente: coletor + applier)
    index.lua               (NamespaceIndex persistido em stdpath('cache'))
    lsp.lua                 (servidor LSP in-process)
  app/
    services/*.lua          (namespace_batch_updater, multi_file_reference_updater, ...)
    operations/*.lua        (file_move, class_rename, namespace_rename, property_rename)
    rename_feature.lua
spec/                       -- testes busted (*_spec.lua) + fixtures PHP
```

Mapeamento de conceitos TS → Lua:
- **tsyringe/DI** → módulos Lua simples; dependências de infra passadas como parâmetro onde o teste precisar trocar (ex.: `fs`, `config`), sem framework.
- **Regex JS (lookbehind, alternância)** → helper `patterns.find_identifier(text, name)` usando `string.find(..., plain=true)` + checagem de vizinhos `[%w_\\]` (equivalente exato a `NOT_PRECEDED/FOLLOWED_BY_NAMESPACE_CHAR`); padrões Lua linha a linha para `namespace`/`use`/declaração de classe.
- **`WorkspaceEdit`** → `infra/edit.lua`: coleta edits por arquivo em offsets de byte (`edit:replace(path, s, e, text)`), aplica em ordem decrescente; se o buffer está carregado usa `nvim_buf_set_text` (um bloco de undo por buffer), senão aplica na string e grava em disco (`edit_files_in_background`; com a flag `false` abre os buffers com `:badd`).
- **`workspace.findFiles`** → `rg --files` / `git ls-files` via `vim.system`, fallback `vim.fs.dir`; filtra `ignored_directories` e extensões.
- **Raiz do workspace** → `vim.fs.root(path, 'composer.json')` (substitui `WORKSPACE_ROOT_PATH` global, suporta vários projetos).
- **Storage do índice** → `stdpath('cache')/php-namespace-refactor/<sha256(root)>.json` com `vim.json`.
- **`window.showInputBox`** → `vim.ui.input` (validação re-pergunta mostrando erro via `vim.notify`).
- **Eventos VS Code** → `BufWritePost *.php` (index), LSP in-process `didRename/didCreate/didDeleteFiles` (explorers), comando manual `move`.
- **Fila serial de `FileRenameHandler`** → fila simples em Lua (lista + flag `running`, processada com `vim.schedule`).

Config (nomes em snake_case, mesmos defaults de `package.json`):
```lua
vim.g.php_namespace_refactor = {
  ignored_directories = { '/vendor/', '/var/', '/cache/' },
  auto_import_namespace = true,
  remove_unused_imports = true,
  additional_extensions = { 'php' },
  rename = true,
  edit_files_in_background = true,
  rename_properties = false, -- ou { rename_mismatched_names = false }
}
```

## Fases (1 commit cada, Conventional Commits em inglês como o histórico, com `Co-Authored-By: Claude Opus 5.5`)

Trabalho numa branch `feat/neovim-migration` (main é a default). Cada fase porta o(s) teste(s) TS correspondente(s) para `spec/` no mesmo commit.

| # | Commit | Conteúdo | Referência TS |
|---|---|---|---|
| 0 | `docs: add neovim migration plan` | `docs/migration-plan.md` (este plano) | — |
| 1 | `chore: scaffold neovim plugin layout` | `plugin/…lua` (guard + comando stub), `lua/php-namespace-refactor/init.lua`, `.stylua.toml`, `.luarc.json`, `selene.toml`, `.editorconfig` | `extension.ts` |
| 2 | `test: add busted + nlua harness` | `.busted`, `spec/minimal_spec.lua`, alvo `make test-lua` | `.vscode-test.mjs` |
| 3 | `ci: add lint, typecheck and test workflow` | `.github/workflows/ci.yaml`: stylua, selene, lua-typecheck-action, nvim-busted-action (nvim 0.10 e stable) | — |
| 4 | `feat(config): add config resolution and validation` | defaults, merge, `vim.validate`, `get_polymorphic_flag` | `ConfigurationLocator`, `FeatureFlagManager`, `PropertyRenameSettingsResolver` (+ test) |
| 5 | `feat(domain): port php patterns` | identificador com fronteira, declaração de classe/enum/trait | `PhpPatterns`, `ClassNameBoundaryRegexBuilder` (+ test) |
| 6 | `feat(domain): port path and extension resolution` | `class_name_from_path`, `extension_from_path`, `normalize_extensions` | `WorkspacePathResolver` (parte pura), `FileExtensionResolver`, `utils/extensions` (+ tests) |
| 7 | `feat(infra): read composer psr-4 autoload` | cache por mtime, namespace↔diretório, `directory_from_namespace` | `infra/autoload/*`, `NamespaceCreator` |
| 8 | `feat(domain): port use statement handling` | locator, creator, injector (gera edits), unused import detector | `UseStatement*`, `UnusedImportDetector` (+ tests) |
| 9 | `feat(infra): add text edit collector and applier` | `edit.lua` + `fs.read_text` (buffer > disco) | `FileEditApplier`, `TextDocumentOpener` |
| 10 | `feat(infra): add workspace file listing` | rg/git/vim.fs fallback, ignore + extensões, cache | `WorkspaceIndex` |
| 11 | `feat(infra): add persistent namespace index` | parse/add/remove/save/load + build incremental assíncrono (chunks com `vim.schedule`) + autocmd `BufWritePost` | `NamespaceIndex`, `NamespaceIndexBuilder`, `FileSavedSubscriber` (+ test) |
| 12 | `feat(app): update namespace and class name of moved file` | | `MovedFileNamespaceUpdater`, `ClassNameUpdater` (+ test) |
| 13 | `feat(domain): port typed property detection` | | `domain/property/*` (+ `ClassTypedPropertyLocator` test) |
| 14 | `feat(app): port property rename operation` | `collect_edits`, `resolve_names` | `PropertyRenameOperation` (+ test) |
| 15 | `feat(app): port multi-file reference updater` | maior peça: índice + scan, FQCN, nome curto, `use` no mesmo diretório | `MultiFileReferenceUpdater`, `NamespaceBatchUpdater` (+ test) |
| 16 | `feat(app): port import remover and missing class importer` | | `ImportRemover`, `MissingClassImporter` |
| 17 | `feat(app): add file move operation with directory expansion` | fila serial, expansão de diretórios | `FileMoveOperation`, `DirectoryMovedFilesResolver`, `FileRenameHandler` |
| 18 | `feat: add :PhpNamespaceRefactor move command` | move físico (`vim.uv.fs_rename` + renomeia buffers abertos) e roda a operação; API `move(old, new)` — **primeiro marco usável** | — |
| 19 | `feat(domain): port rename detection and validation` | | `rename/*` (+ `RenameTypeDetector` test) |
| 20 | `feat: add rename command and <Plug> mapping` | `vim.ui.input`, class/namespace rename → reusa move; checa flag `rename` | `RenameFeature`, `RenameHandler`, `Class/NamespaceRenameOperation` |
| 21 | `feat(lsp): add in-process lsp for explorer file operations` | `vim.lsp.start({ cmd = function… })` em `FileType php` dentro de raiz composer; anuncia `workspace.fileOperations.didRename/didCreate/didDelete` (`**/*.php` e pastas) → move operation + atualização do índice | `onDidRenameFiles`, `FileCreated/DeletedSubscriber` |
| 22 | `feat: add health check` | versão nvim, composer.json/psr-4, rg/git, config inválida/chaves desconhecidas, LSP ativo | — |
| 23 | `docs: add vimdoc and rewrite readme for neovim` | `doc/php-namespace-refactor.txt`, README (lazy.nvim, config, mapping F2, explorers suportados), atualiza `docs/*.md` | `README.md`, `docs/` |
| 24 | `chore!: remove vscode extension sources` | remove `src/`, `package*.json`, `esbuild.js`, `eslint.config.mjs`, `tsconfig.json`, `.vscode*`, `test-setup/`, `vsc-extension-quickstart.md`, `node_modules` do ignore; Makefile só Lua | — |
| 25 | `ci: switch release-please to simple release type` | `release-type: simple`, remove `extra-files`, versão em `version.txt`; (opcional) rockspec + luarocks-tag-release | `release-please-config.json` |

Fases 4–17 são independentes de UI e cada uma é testável só com busted; 18 é o primeiro ponto de teste manual ponta a ponta.

## Riscos / pontos de atenção

- **Regex JS → Lua**: maior risco de regressão; mitigado portando os testes TS (`PhpPatterns.test`, `MultiFileReferenceUpdater.test`) quase literalmente.
- **Offsets UTF-8**: edits trabalham em bytes; ao aplicar em buffer converter offset → (linha, coluna em bytes) — consistente com `nvim_buf_set_text`.
- **Atomicidade do undo** multi-arquivo não existe no Nvim; cada buffer recebe um bloco único de undo. Documentar.
- **Performance**: scan do workspace é síncrono durante a operação (iniciada pelo usuário); o build do índice é incremental e lazy (no primeiro `FileType php` dentro de uma raiz composer, não no startup).
- **LSP in-process**: alguns explorers só mandam `willRenameFiles`; registrar ambos (`willRename` retorna edit vazio, `didRename` dispara a operação). oil precisa de `lsp_file_methods` habilitado (default). mini.files não usa LSP → documentar ou adapter `User MiniFilesActionRename` depois.

## Verificação

- Por fase: `make test-lua` (busted via nlua), `stylua --check .`, `selene .`, typecheck LuaLS; CI verde em nvim 0.10 e stable.
- Ponta a ponta (a partir da fase 18): projeto PHP fixture em `spec/fixtures/project` com `composer.json` PSR-4; em `nvim --clean -u spec/minimal_init.lua`:
  1. `:PhpNamespaceRefactor move src/Foo/Bar.php src/Baz/Bar.php` → namespace do arquivo e `use` dos dependentes atualizados.
  2. Cursor em `class Bar` → `<Plug>(PhpNamespaceRefactorRename)` → novo nome renomeia arquivo e referências (e propriedades com `rename_properties = true`).
  3. Fase 21: mover arquivo pelo neo-tree/oil/snacks e confirmar o mesmo resultado.
  4. `:checkhealth php-namespace-refactor` sem erros.
