#!/bin/bash
set -Eeuo pipefail

# Variables
GVM_ROOT="$HOME/gvm"
GO_BIN_URL="https://mirrors.aliyun.com/golang"
BASHRC_FILE="$HOME/.bashrc"

[ -d "$GVM_ROOT" ] || {
	echo "Directory already exists $GVM_ROOT"
	exit 1
}

function help() {
    cat <<EOF
Usage:
  $(basename "$0") help | -h | --help

  $(basename "$0") install <version_id>
  $(basename "$0") uninstall <version_id>
  $(basename "$0") switch <version_id>
  $(basename "$0") list (installed|all|active)
  $(basename "$0") version

Options:
  install         Install the specified Go version
  uninstall       Uninstall the specified Go version
  switch          Switch to the specified Go version
  list            List Go versions (installed, all, or active)
  version         Show the go-version-manager version
EOF
}

function list_help() {
    cat <<EOF
List installed, all, or active Go versions.

Usage:
  $(basename "$0") list (installed|all|active)

Options:
  installed       List installed Go versions
  all             List all available Go versions
  active          List the currently used Go version
EOF
}

function parse_param() {
    case "$1" in
        install)
            [ -z "$2" ] && {
                echo "Error: Go version is required for install"
                help
                exit 1
            }
            install "$2"
            ;;
        uninstall)
            [ -z "$2" ] && {
                echo "Error: Go version is required for uninstall"
                help
                exit 1
            }
            uninstall "$2"
            ;;
        switch)
            [ -z "$2" ] && {
                echo "Error: Go version is required for switch"
                help
                exit 1
            }
            switch "$2"
            ;;
        list)
            case "$2" in
                installed)
                    list_installed
                    ;;
                all)
                    list_all
                    ;;
                active)
                    list_active
                    ;;
                -h | --help)
                    list_help
                    ;;
                *)
                    echo "Error: Invalid option for list"
                    list_help
                    exit 1
                    ;;
            esac
            ;;
        --version | -v)
            version
            ;;
        --help | -h)
            help
            ;;
        *)
            echo "Error: Invalid command"
            help
            exit 1
            ;;
    esac
}

function add_go_env() {
	local go_root="$1"
	local go_path="$HOME/go"

	mkdir -p "$go_path/bin" "$go_path/src" "$go_path/pkg"

  if [ "$(tail -n 1 "$BASHRC_FILE")" != "" ]; then
    echo "" >> "$BASHRC_FILE"
  fi

	env_vars=(
	  "# set the golang environment variable to the system"
		"export GOROOT=/usr/local/go"
		"export GOPATH=$go_path"
		"export PATH=\$PATH:\$GOROOT/bin:\$GOPATH/bin"
	)

	if [ ! -f "$BASHRC_FILE.bak" ]; then
		cp "$BASHRC_FILE" "$BASHRC_FILE.bak"
	fi

	for var in "${env_vars[@]}"; do
		if ! grep -qF "$var" "$BASHRC_FILE"; then
			echo "$var" >>"$BASHRC_FILE"
			echo "Added $var to $BASHRC_FILE" &>/dev/null
		else
			echo "$var already exists in $BASHRC_FILE" &>/dev/null
		fi
	done

	[ -d /usr/local/go ] && rm -rf /usr/local/go
	ln -sv "${go_root}" "/usr/local/go"  &>/dev/null

	source ${BASHRC_FILE}
}


# Install Go version
function install() {
	local version=$1
	local install_dir="$GVM_ROOT/go$version"
	if [ -d "$install_dir" ]; then
		echo "Go version $version is already installed."
		return
	fi
	echo "Installing Go version $version..."
	local os=$(uname | tr '[:upper:]' '[:lower:]')
	local arch=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
	local tarball="go${version}.${os}-${arch}.tar.gz"
	if [ ! -f ${GVM_ROOT}/${tarball} ]; then
		wget "$GO_BIN_URL/$tarball" -P "$GVM_ROOT" &>/dev/null
		echo "Downloaded and saved to ${tarball}"
	else
		echo "${tarball} is exists"
	fi

	tar -C "$GVM_ROOT" -xzf "$GVM_ROOT/$tarball" || {
		echo "Failed to extract Go tarball"
		exit 1
	}
	mv "$GVM_ROOT/go" "$install_dir"
	rm "$GVM_ROOT/$tarball"
	echo "Go version $version installed successfully."
	add_go_env $install_dir
}

# Uninstall Go version
function uninstall() {
	local version=$1
	local install_dir="$GVM_ROOT/go$version"
	if [ ! -d "$install_dir" ]; then
		echo "Go version $version is not installed."
		return
	fi
	echo "Uninstalling Go version $version..."
	rm -rf "$install_dir" || {
		echo "Failed to uninstall Go version $version"
		exit 1
	}
	echo "Go version $version uninstalled successfully."
	current_exists_versions=$(ls -1 "$GVM_ROOT" | grep '^go' | sed -n 's/^go\([0-9.]\+\)$/\1/p')
  if [ -z "$current_exists_versions" ]; then
    cp "$BASHRC_FILE.bak" "$BASHRC_FILE"
  fi
}

# Switch Go version
function switch() {
	local version=$1
	local install_dir="$GVM_ROOT/go$version"
	if [ ! -d "$install_dir" ]; then
		echo "Go version $version is not installed."
		return
	fi
	echo "Switching to Go version $version..."
	BASHRC_FILE="$HOME/.bashrc"

	[ -d /usr/local/go ] && rm -rf /usr/local/go
	ln -sv "${install_dir}" "/usr/local/go" &>/dev/null

	source "$BASHRC_FILE"
	echo "Switched to Go version $version."
}

# List installed Go versions
function list_installed() {
  local current_exists_versions=$(ls -1 "$GVM_ROOT" | grep '^go' | sed -n 's/^go\([0-9.]\+\)$/\1/p')
  if [ -z "$current_exists_versions" ]; then
    echo "There is no available go version"
    return
  fi
  echo "Installed Go versions:"
  ls -1 "$GVM_ROOT" | grep '^go' | sed -n 's/^go\([0-9.]\+\)$/\1/p' | awk '{print "  " $0}'
}

# List installed Go versions
function list_active() {
  local go_version=$(go version)
  echo "$go_version"
}

# List all available online Go versions
function list_all() {
	local page_content=$(curl -s ${GO_BIN_URL}/)
	local all_versions=$(echo "$page_content" | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -u)
	local clean_versions=$(echo "$all_versions" | sed 's/go//g')
	local latest_version=$(echo "$clean_versions" | sort -Vr | head -n 1)
	local stable_versions=$(echo "$clean_versions" | grep -v "^$latest_version$" | sort -Vr)
	local latest_stable_version=$(echo "$stable_versions" | head -n 1)

	echo "All Stable Go versions:"
	echo "$stable_versions" | awk '{print "  " $0}'
	echo
	echo "Latest stable Go version:"
	echo "$latest_stable_version" | awk '{print "  " $0}'
	echo
	echo "Unstable Go version:"
	echo "$latest_version" | awk '{print "  " $0}'
}

# Show the script version
function version() {
	echo "go-version-manager.sh version 1.0.0"
}


function main() {
    if [ $# -eq 0 ]; then
        echo "Error: No command provided"
        help
        exit 1
    fi

    parse_param "$@"
}

main "$@"
