rockspec_format = '3.0'
package = 'php-namespace-refactor.nvim'
version = 'scm-1'

source = {
  url = 'git+https://github.com/rejmann/php-namespace-refactor.nvim',
}

description = {
  summary = 'Refactor PHP namespaces and references when moving or renaming files in Neovim',
  homepage = 'https://github.com/rejmann/php-namespace-refactor.nvim',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
}

build = {
  type = 'builtin',
  copy_directories = {
    'plugin',
  },
}
