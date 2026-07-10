#!/bin/sh -eu

# This script is meant to be run by the devcontainer CLI on a devcontainer after
# its creation. It belongs to a dotfiles repository, and can be used to set up
# dotfile-specific system configuration. See:
# https://github.com/devcontainers/cli/pull/362

USER="$(id -un)"
readonly USER

# Elevate permissions to perform system modifications
if [ "$USER" != 'root' ]; then
  exec sudo "$0" "$USER" "$@"
fi

readonly ORIGINAL_USER="$1"
shift

# Install nixpkgs packages the devcontainer flake omits ($1 = attr, $2 = binary),
# symlinking each into /usr/local/bin so it's on PATH for all users (the root Nix
# profile isn't). Neovim must be recent enough for Neovide; rg/fd are conveniences.
nix_link() {
  profile=/nix/var/nix/profiles/per-user/root/profile
  mkdir -p "${profile%/*}"
  nix profile add --profile "$profile" "nixpkgs#$1"
  ln -sf "$profile/bin/$2" "/usr/local/bin/$2"
}

# Download a binary from a GitHub release into /usr/local/bin and mark it
# executable. With a third argument the asset is assumed to be a gzipped
# tarball, and it names the member to extract.
install_gh_release_bin() {
  if [ -n "${3:-}" ]; then
    curl -sSL "$1" | tar -xzf - -C /usr/local/bin "$3"
  else
    curl -sSL "$1" -o "/usr/local/bin/$2"
  fi
  chmod a+x "/usr/local/bin/$2"
}

# Fetch the OS and architecture for binaries to install below.
case "$(uname -s)" in
Linux)
  make_ls_os=linux
  dbr_os=unknown-linux-musl
  ;;
Darwin)
  make_ls_os=darwin
  dbr_os=apple-darwin
  ;;
*)
  echo "Unsupported OS $(uname -s)" >&2
  exit 1
  ;;
esac
case "$(uname -m)" in
x86_64 | amd64)
  make_ls_arch=amd64
  dbr_arch=x86_64
  ;;
aarch64 | arm64)
  make_ls_arch=arm64
  dbr_arch=aarch64
  ;;
*)
  echo "Unsupported architecture $(uname -m)" >&2
  exit 1
  ;;
esac

echo '> Restoring man pages...'
yes | unminimize

echo '> Installing CLI tools via Nix...'
nix_link neovim nvim
nix_link ripgrep rg
nix_link fd fd
nix_link lazygit lazygit
nix_link opencode opencode

echo '> Installing make-ls...'
readonly MAKE_LS_VERSION=0.1.12
install_gh_release_bin \
  "https://github.com/owenrumney/make-ls/releases/download/v${MAKE_LS_VERSION}/make-ls_${make_ls_os}_${make_ls_arch}.tar.gz" \
  make-ls make-ls

echo '> Installing devcontainer-bridge (dbr)...'
readonly DBR_VERSION=0.3.0
install_gh_release_bin \
  "https://github.com/bradleybeddoes/devcontainer-bridge/releases/download/v${DBR_VERSION}/dbr-${dbr_arch}-${dbr_os}" \
  dbr
ln /usr/local/bin/dbr /usr/local/bin/dbr-open # Link used below

echo '> Creating xdg-open -> dbr-open wrapper...'
cat <<'EOF' >/usr/local/bin/xdg-open
#!/bin/sh
exec dbr-open "$@"
EOF
chmod a+x /usr/local/bin/xdg-open

echo '> Fixing up /workspaces directory permissions...'
chown vscode /workspaces

echo '> Copying dotfiles...'
sudo -u "$ORIGINAL_USER" sh -c 'cp -R .config ~'

echo '> Setting up Neovim...'
sudo -u "$ORIGINAL_USER" nvim --headless '+Lazy! sync' +qa
