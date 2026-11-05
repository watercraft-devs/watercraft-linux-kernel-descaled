#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# hail: basically a formatted alias for echo or printf, use it to announce stuff
hail() {
        if [ -x /usr/bin/pad_cpp ]; then
                printf "\n%s\n" "$(/usr/bin/pad_cpp "$*" 64 = c)"
	elif [ -x /usr/local/bin/pad_cpp ]; then
		printf "\n%s\n" "$(/usr/local/bin/pad_cpp "$*" 64 = c)"
        else
                printf "\n%s\n" "$*"
        fi
}


basedir="$PWD"

hail "recording baseline kernel version, name, and rust status"

kernelname="$(uname -r )"
kernelversion="$(apt policy linux-image-amd64 2>/dev/null | awk '/Installed:/{print $2}')"

#printf "\n%s\n" "$kernelversion"

kerneldir="linux-${kernelversion%-*}"


wcv="wc1" #watercraft kernel version

kernelruststatus="$(grep -i rust /boot/config-"$kernelname")"

#printf "\n%s\n" "$kernelruststatus"

cat <<EOF > baseline.txt
kernel name: $kernelname
kernel version: $kernelversion

kernel rust status:

$kernelruststatus
EOF


hail "preparing build host"

hail "running update..."

sudo apt update

hail "checking for expected sources..."

sourcescheck="$(grep -rh '^deb-src' /etc/apt/sources.list /etc/apt/sources.list.d/)"

expected="deb-src http://deb.devuan.org/merged excalibur main non-free-firmware
deb-src http://deb.devuan.org/merged excalibur-security main non-free-firmware
deb-src http://deb.devuan.org/merged excalibur-updates main non-free-firmware"

if [[ $sourcescheck != $expected ]]; then
	hail "expected sources not found!\n"
	exit 1
fi

hail "expected sources available..."

hail "installing build dependencies..."

sudo apt build-dep linux
sudo apt install build-essential fakeroot libncurses-dev bc kmod cpio flex \
                 bison libssl-dev libelf-dev rsync dwarves zstd


hail "verifying absence of rust toolchain" 
rusttoolchaincheck="$(command -v rustc )"

if [[ "$rusttoolchaincheck" != "" ]]; then
	hail "rust toolchain detected!" 
	hail "$rusttoolchaincheck"
	exit 1
fi

hail "no rust toolchain found... proceeding"


hail "fetching kernel source..."

apt source linux="$kernelversion"

pushd "$kerneldir" > /dev/null 


hail "recording pre build artifacts"

#cp debian/patches/series series."$kernelversion".backup

artifactsdir="$basedir"/artifacts/"$kernelversion""$wcv"
mkdir -p "$artifactsdir"

ls

tar -xOf "$basedir"/linux_"$kernelversion".debian.tar.xz debian/patches/series \
    > "$artifactsdir/patch-series.txt"

cp .config "$artifactsdir/config"

grep '^CONFIG_RUST' .config > "$artifactsdir/rust-probe.txt"


sha256sum "$basedir"/linux-*.deb > "$artifactsdir/SHA256SUMS"


hail "configuring build"

cp /boot/config-"$kernelname" .config
scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
scripts/config --disable DEBUG_INFO --enable DEBUG_INFO_NONE
scripts/config --disable MODULE_SIG_ALL
make olddefconfig


hail "final rust-free checks before build"

command -v rustc && { hail "error: rustc present in build env!"; exit 1;  }

if  grep -q '^CONFIG_RUST=y' .config; then
	hail "error: rust enabled in .config!"; exit 1;
elif grep -q '# CONFIG_RUST is not set' .config; then
	hail "Rust available but disabled, still OK"
else
	hail "Rust not available in this build environment at all"
fi


hail "Prepared to build the rust-free / descaled Linux Kernel"

hail "This WILL LIKELY take several minutes and will work your CPU to near 100% load!"

read -p "Ready? (y/n): " buildyn

build() {

	hail "building descaled Linux kernel"
	(
		make -j"$(nproc)" bindeb-pkg \
			LOCALVERSION=-wc-descaled-amd64 \
			KDEB_PKGVERSION="$kernelversion""$wcv"
	)

}


case "$buildyn" in [Yy]|[Yy][Ee][Ss]) build ;;
        *) hail "Builder rejected the build from proceeding..." ;;
esac

# TODO replace "$kerneldir" with something that just strips everything after the - ONCE
# then source from that variable in every following instance where it's needed

postbuild() {
	hail "Post Build"

	[[ -f "vmlinux" ]] || { "FAIL: vmlinux missing - cannot verify build!"; exit 1;  }
	[[ -f ".config" ]] || { "FAIL: .config missing - cannot verify build!"; exit 1;  }

	
	hail "Checking for Rust mangled symbols in the image..."

	mangled="$(nm vmlinux | grep -c ' _R[A-Z]' )"

	if [[ "$mangled" != "0" ]]; then
		hail "FAIL: mangled Rust symbols found"
		exit 1
	fi
	hail "PASSED!"

	hail "Checking for any Rust objects compiled..."

	objects="$(find rust -name '*.o' | wc -l)"

	if [[ "$objects" != "0" ]]; then
		hail "FAIL: compiled Rust objects found"
		exit 1
	fi
	hail "PASSED!"

	hail "Checking that CONFIG_RUST was never enabled..."

	config="$(grep -c '^CONFIG_RUST=' .config )"

	if [[ "$config" != "0" ]]; then
		hail "FAIL: Rust config was enabled"
		exit 1
	fi
	hail "PASSED!"

	hail "Checking VERSION=0 for RUSTC and LLVM..."

	rustc_version_check="$(grep -cx 'CONFIG_RUSTC_VERSION=0' .config )"
	if [[ "$rustc_version_check" != "1" ]]; then
		hail "FAIL: CONFIG_RUSTC_VERSION is not 0"
		exit 1
	fi

	llvm_version_check="$(grep -cx 'CONFIG_RUSTC_LLVM_VERSION=0' .config )"
	if [[ "$llvm_version_check" != "1" ]]; then
		hail "FAIL: CONFIG_RUSTC_LLVM_VERSION is not 0"
		exit 1
	fi


	hail "PASSED!"

	hail "100% of Rust-free post build checks passed!" 
	
	hail "ZERO Rust in this kernel build!"

}

read -p "Run the post build check scripts? (y/n): " postbuildyn

case "$postbuildyn" in [Yy]|[Yy][Ee][Ss]) postbuild ;;
	*) exit 0
esac


