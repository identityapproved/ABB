# Helpers for Arch AUR workflows powered by yay

function aur-install() {
  yay -S "$@"
}

function aur-update() {
  yay -Sua "$@"
}

function aur-clean() {
  yay -Yc
}

function aur-search() {
  yay -Ss "$@"
}

compdef aur-install=yay
compdef aur-update=yay
compdef aur-clean=yay
compdef aur-search=yay
