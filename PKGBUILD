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
    'cronie: crontab management when INSTALL_CRONTAB=true'
)
backup=('etc/system-update/config.conf')
install=awesome-updater.install

# Project is self-contained; files live next to this PKGBUILD.
#
# The `name::url` alias syntax in makepkg is only meaningful for remote
# sources. For local files makepkg uses the left side of "::" as the
# destination filename in $srcdir, which causes it to look for that name
# in the build directory. Local files must therefore be declared with
# their natural relative path; makepkg copies each into $srcdir under its
# basename. package() references those flat names.
source=(
    'system-update'
    'system-update-notify'
    'profile.d/99-system-update.sh'
    'config/config.conf'
    'man/system-update.1'
    'man/system-update-notify.1'
    'README.md'
    'LICENSE'
)
sha256sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

prepare() {
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

    install -Dm644 "$srcdir/system-update.1" \
        "$pkgdir/usr/share/man/man1/system-update.1"

    install -Dm644 "$srcdir/system-update-notify.1" \
        "$pkgdir/usr/share/man/man1/system-update-notify.1"

    install -Dm644 "$srcdir/README.md" \
        "$pkgdir/usr/share/doc/$pkgname/README.md"

    install -Dm644 "$srcdir/LICENSE" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}