# Maintainer: Gyöngyösi Gábor <gabor at gshoots dot hu>
pkgname=awesome-updater
pkgver=0.1.0
pkgrel=1
pkgdesc="Manjaro-focused unattended system updater with kernel reboot handling"
arch=('any')
url="https://github.com/megvadulthangya/awesome-updater"
license=('MIT')
depends=(
    'bash'
    'coreutils'
    'inetutils'
    'kernel-modules-hook'
    'pacman'
    'systemd'
    'findutils'
    'gawk'
    'grep'
    'sed'
    'util-linux'
)
optdepends=(
    'git: AUR support when AUR_ENABLED=true'
    'base-devel: AUR support when AUR_ENABLED=true'
    'libnotify: GUI desktop notifications via notify-send'
)
backup=('etc/system-update/config.conf')
install=awesome-updater.install

# Only files that live at the top level of the repository can be declared
# directly in source=(). makepkg resolves local source entries against the
# directory where it was invoked and does not search subdirectories; the
# name::path alias form is only meaningful for remote sources. Files under
# profile.d/, config/, man/ and systemd/ are therefore staged into $srcdir
# by prepare() using $startdir (which makepkg sets to the directory where
# it was invoked), and package() installs them normally.
source=(
    'system-update'
    'system-update-notify'
    'README.md'
    'LICENSE'
)
sha256sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

prepare() {
    # Stage subdirectory sources into $srcdir under their basenames so that
    # package() can install them normally.
    cp -a "$startdir/profile.d/99-system-update.sh" "$srcdir/99-system-update.sh"
    cp -a "$startdir/config/config.conf"            "$srcdir/config.conf"
    cp -a "$startdir/man/system-update.1"           "$srcdir/system-update.1"
    cp -a "$startdir/man/system-update-notify.1"    "$srcdir/system-update-notify.1"
    cp -a "$startdir/systemd/awesome-updater@.service" "$srcdir/awesome-updater@.service"
    cp -a "$startdir/systemd/awesome-updater@.timer"   "$srcdir/awesome-updater@.timer"

    # Single-source the runtime version string from pkgver.
    sed -i "s/@VERSION@/$pkgver/g" "$srcdir/system-update"
}

build() {
    : # nothing to build
}

package() {
    install -Dm755 "$srcdir/system-update" \
        "$pkgdir/usr/bin/system-update"

    install -Dm755 "$srcdir/system-update-notify" \
        "$pkgdir/usr/bin/system-update-notify"

    install -Dm644 "$srcdir/99-system-update.sh" \
        "$pkgdir/etc/profile.d/99-system-update.sh"

    install -Dm644 "$srcdir/config.conf" \
        "$pkgdir/etc/system-update/config.conf"

    install -Dm644 "$srcdir/awesome-updater@.service" \
        "$pkgdir/usr/lib/systemd/system/awesome-updater@.service"

    install -Dm644 "$srcdir/awesome-updater@.timer" \
        "$pkgdir/usr/lib/systemd/system/awesome-updater@.timer"

    install -Dm644 "$srcdir/system-update.1" \
        "$pkgdir/usr/share/man/man1/system-update.1"

    install -Dm644 "$srcdir/system-update-notify.1" \
        "$pkgdir/usr/share/man/man1/system-update-notify.1"

    install -Dm644 "$srcdir/README.md" \
        "$pkgdir/usr/share/doc/$pkgname/README.md"

    install -Dm644 "$srcdir/LICENSE" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}