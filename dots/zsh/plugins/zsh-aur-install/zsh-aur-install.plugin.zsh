# Helpers for Arch AUR workflows powered by yay

_abb_require_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi
  print -u2 "yay is not installed yet. Run 'abb-setup.sh package-manager' first."
  return 1
}

function aur-install() {
  _abb_require_yay || return 1
  yay -S "$@"
}

function aur-update() {
  _abb_require_yay || return 1
  yay -Sua "$@"
}

function aur-clean() {
  _abb_require_yay || return 1
  yay -Yc
}

function aur-search() {
  _abb_require_yay || return 1
  yay -Ss "$@"
}

if command -v yay >/dev/null 2>&1; then
  compdef aur-install=yay
  compdef aur-update=yay
  compdef aur-clean=yay
  compdef aur-search=yay
fi
