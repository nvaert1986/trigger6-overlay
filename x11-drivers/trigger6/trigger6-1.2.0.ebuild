# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1 systemd toolchain-funcs udev

DESCRIPTION="DRM/KMS driver for MCT Trigger 6 USB to HDMI adapters (StarTech USB32HDES)"
HOMEPAGE="https://github.com/nvaert1986/trigger6-kernel-module"
# The release tag tarball, renamed so it can never collide in DISTDIR.
SRC_URI="https://github.com/nvaert1986/trigger6-kernel-module/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/trigger6-kernel-module-${PV}"

# Module and helper are both GPL-2.0-only (LICENSE in the tarball).
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

# The helper links only libc (DT_NEEDED: libc.so.6; it uses dlopen from libc
# 2.34+). It loads libyuv at run time instead:
#
#   dlopen("libyuv.so.0"), then dlopen("libyuv.so")  -> media-libs/libyuv
#
# Without libyuv the helper cannot convert and the driver falls back to its
# in-kernel conversion (about 29 instead of 60 frames per second).
RDEPEND="media-libs/libyuv"

pkg_setup() {
	# kernel/Kbuild and the driver's requirements (README "Requirements").
	# SND_PCM only adds the HDMI sound card; the display works without it.
	local CONFIG_CHECK="MODULES ~DRM ~DRM_KMS_HELPER ~DRM_GEM_SHMEM_HELPER ~USB ~SND_PCM"
	local ERROR_SND_PCM="CONFIG_SND_PCM is not set: the module builds without its HDMI audio sound card."
	linux-mod-r1_pkg_setup
}

src_compile() {
	# kernel/Makefile builds with "make -C \$(KSRC) M=\$(CURDIR) modules".
	local modlist=( trigger6=video:kernel )
	local modargs=( KSRC="${KV_OUT_DIR}" KVER="${KV_FULL}" )
	linux-mod-r1_src_compile

	# Same command as README section C, with the user's flags.
	$(tc-getCC) ${CFLAGS} ${CPPFLAGS} -pthread -o trigger6-fast \
		userspace/trigger6-fast.c ${LDFLAGS} -ldl || die
}

src_install() {
	linux-mod-r1_src_install

	dobin trigger6-fast

	# Upstream's own files from the tarball (packaging/debian13/): the udev
	# rule gives the seat user access to the adapter and starts the helper as
	# a systemd user service when its device node appears; trigger6.conf makes
	# the module hand frames to that helper.
	udev_dorules packaging/debian13/71-trigger6.rules
	systemd_douserunit packaging/debian13/trigger6-fast.service
	insinto /etc/modprobe.d
	doins packaging/debian13/trigger6.conf

	dodoc README.md
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst
	udev_reload

	# Files from the manual install in the upstream README (sections C and D).
	# The two under /etc take precedence over this package's copies in
	# /usr/lib, and that service file starts the old /usr/local/bin helper.
	local f leftovers=()
	for f in /etc/systemd/user/trigger6-fast.service \
		/etc/udev/rules.d/71-trigger6.rules /usr/local/bin/trigger6-fast; do
		[[ -e ${EROOT}${f} ]] && leftovers+=( "${EROOT}${f}" )
	done
	if [[ ${#leftovers[@]} -gt 0 ]]; then
		ewarn "Files from a manual install override this package; remove them:"
		ewarn
		ewarn "  rm ${leftovers[*]}"
		ewarn "  udevadm control --reload-rules"
		ewarn
		ewarn "then, as your desktop user: systemctl --user daemon-reload"
		ewarn
	fi

	if [[ -n ${REPLACING_VERSIONS} ]]; then
		elog "Unplug the adapter, reload the module (modprobe -r trigger6) and plug it in"
		elog "again to run the new version."
	else
		elog "Plug in the adapter. On systemd the udev rule starts the helper"
		elog "(trigger6-fast, a systemd user service) by itself; check with:"
		elog
		elog "  systemctl --user status trigger6-fast"
		elog
		elog "Without systemd, start 'trigger6-fast' in the desktop session yourself."
		elog "On Xorg, unplugging the USB adapter crashes the X server (an Xorg bug);"
		elog "Wayland is not affected. See ${EROOT}/usr/share/doc/${PF}/README.md*."
	fi
}

pkg_postrm() {
	udev_reload
}
