set scrolloff=8
" Tab Options
set tabstop=2 
set softtabstop=2
set shiftwidth=2
set expandtab

" Disable backups and swap files
set nobackup
set nowritebackup
set noswapfile
set nocompatible

" Indentation
set smartindent

" Numbers
set number
set relativenumber

" Fix splitting
set splitbelow splitright

set hidden " Open other files if current one is not saved

set ignorecase " Ignore case when searching
set smartcase  " When searching try to be smart about cases
set hlsearch! " Don't highlight search term
set incsearch  " Jumping search

" Always show the status line
set laststatus=2

" Horisontal/vertical line on cursor location
set cursorline
" set cursorcolumn

set encoding=UTF-8
set timeout timeoutlen=500
set lazyredraw
set ttyfast
set backspace=indent,eol,start

call plug#begin('~/.vim/plugged')

Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'liuchengxu/vim-which-key'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'majutsushi/tagbar'
Plug 'andymass/vim-matchup'
Plug 'jiangmiao/auto-pairs'
Plug 'editorconfig/editorconfig-vim'
Plug 'mhinz/vim-startify'
Plug 'machakann/vim-highlightedyank'
Plug 'tpope/vim-sensible'
Plug 'RRethy/vim-illuminate'
Plug 'dense-analysis/ale'
Plug 'ojroques/vim-oscyank', {'branch': 'main'}

Plug 'ghifarit53/tokyonight-vim'

Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
" Plug 'bling/vim-bufferline'

Plug 'psliwka/vim-smoothie'
Plug 'Yggdroot/indentLine'

" Plug 'mhinz/vim-sayonara', { 'on': 'Sayonara' }

" Frontend related
Plug 'ap/vim-css-color'
Plug 'ryanoasis/vim-devicons'
Plug 'mattn/emmet-vim'

" Python
Plug 'vim-python/python-syntax'
Plug 'davidhalter/jedi-vim'

Plug 'preservim/nerdtree'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'PhilRunninger/nerdtree-buffer-ops'
Plug 'PhilRunninger/nerdtree-visual-selection'
Plug 'Xuyuanp/nerdtree-git-plugin'

Plug 'preservim/nerdcommenter'

Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'sheerun/vim-polyglot'

call plug#end()

" OSC52 clipboard copy helpers
nmap <leader>c <Plug>OSCYankOperator
nmap <leader>cc <leader>c_
vmap <leader>c <Plug>OSCYankVisual

" CoC extensions
let g:coc_global_extensions = [
      \ 'coc-json',
      \ 'coc-tsserver',
      \ 'coc-pyright',
      \ 'coc-html',
      \ 'coc-css'
      \ ]
set updatetime=300
autocmd CursorHold * silent call CocActionAsync('highlight')

" Coc&NERDTree settings
source $HOME/.vim/modules/coc.vim
source $HOME/.vim/modules/nerdtree.vim

" Airline
let g:airline#extensions#tabline#enabled = 1 " Enable the list of buffers
let g:airline#extensions#tabline#formatter = 'unique_tail_improved' " f/p/file-name.js
let g:airline_powerline_fonts = 1
let g:airline_theme='tokyonight'

" Theme
set termguicolors
" set notermguicolors
" set background=dark
" set t_Co=256
" hi clear
" syntax on
let g:tokyonight_style = 'night' " available: night, storm
let g:tokyonight_enable_italic = 1
let g:tokyonight_transparent_background = 1
let g:tokyonight_menu_selection_background = 'blue'
colorscheme tokyonight

" Transparent background
" hi Normal     ctermbg=NONE guibg=NONE
" hi LineNr     ctermbg=NONE guibg=NONE
" hi SignColumn ctermbg=NONE guibg=NONE

" Indentation
let g:indentLine_char_list = ['|', '¦', '┆', '┊']

let mapleader = " "
nnoremap <leader>pv :Vex<CR>
nnoremap <leader>ps :Sex<CR>
nnoremap <silent><leader><CR> :so ~/.vimrc \| :PlugInstall<CR>
nnoremap <leader>pf :GFiles<CR>
nnoremap <C-p> :Files<CR>
nnoremap <C-j> :cnext<CR>
nnoremap <C-k> :cprev<CR>

nnoremap <silent><F7> :set hlsearch!<CR>

vnoremap <leader>p "_dP
vnoremap <leader>y "+y
nnoremap <leader>y "+cy
nnoremap <leader>Y gg"+yG 
" nnoremap <C-b> <Esc>:Lex<CR>:vertical resize 23<CR>
nnoremap <silent><C-b> :NERDTreeToggle<CR>

nnoremap <PageUp>   :bprevious<CR>
nnoremap <PageDown> :bnext<CR>
nnoremap <silent> <C-h> :vertical resize -2<CR>
nnoremap <silent> <C-l> :vertical resize +2<CR>
nnoremap <silent> <C-j> :resize +2<CR>
nnoremap <silent> <C-k> :resize -2<CR>
nnoremap <leader>tt :TagbarToggle<CR>

" fzf keybindings
command! FzfMaps call fzf#run(fzf#wrap({
      \ 'source': split(execute('verbose map'), "\n"),
      \ 'sink':   'echo',
      \ 'options': '--prompt "Keymap> " --ansi --reverse'
      \ }))
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fg :Rg<CR>
nnoremap <leader>fb :Buffers<CR>
nnoremap <leader>fo :History<CR>
nnoremap <leader>fm :FzfMaps<CR>

" which-key configuration
let g:which_key_map = {}
let g:which_key_map['f'] = [ ':Files', 'Find files' ]
let g:which_key_map['g'] = [ ':GFiles', 'Git files' ]
let g:which_key_map['b'] = [ ':Buffers', 'Buffers' ]
let g:which_key_map['o'] = [ ':History', 'History' ]
let g:which_key_map['m'] = [ ':FzfMaps', 'Keymaps' ]
let g:which_key_map.s = {
      \ 'name' : '+search',
      \ 'f' : [':Files', 'files'],
      \ 'g' : [':GFiles', 'git files'],
      \ 'r' : [':Rg', 'ripgrep'],
      \ }
nnoremap <silent> <leader> :WhichKey '<Space>'<CR>
vnoremap <silent> <leader> :WhichKeyVisual '<Space>'<CR>
call which_key#register('<Space>', 'g:which_key_map')

vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Emmet shortcuts
let g:user_emmet_mode='n'
let g:user_emmet_leader_key=','
