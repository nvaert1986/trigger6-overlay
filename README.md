# trigger6-overlay

A Portage overlay for [trigger6](https://github.com/nvaert1986/trigger6-kernel-module), the Linux DRM/KMS
driver for MCT Trigger 6 USB to HDMI adapters (StarTech USB32HDES, USB ID `0711:5601`).

| Package | Source | Installs | Notes |
|---|---|---|---|
| `x11-drivers/trigger6` | Release tag tarball, built from source | Kernel module, `trigger6-fast` helper, udev rule, systemd user service, modprobe options | Module built with `linux-mod-r1` (signed with `USE=modules-sign`); helper loads `media-libs/libyuv` |

## Layout

```
trigger6-overlay/
├── metadata/layout.conf
├── profiles/{repo_name,categories}
└── x11-drivers/trigger6/
    ├── trigger6-1.1.0.ebuild
    └── metadata.xml · Manifest
```

## Installing the overlay (as root)

Portage runs as `portage:portage`, so the overlay belongs in the standard
root-owned location, `/var/db/repos/trigger6-overlay` — not in a home directory.

```bash
cat > /etc/portage/repos.conf/trigger6-overlay.conf <<'CONF'
[trigger6-overlay]
location = /var/db/repos/trigger6-overlay
sync-type = git
sync-uri = https://github.com/nvaert1986/trigger6-overlay.git
auto-sync = yes
masters = gentoo
priority = 50
CONF

emaint sync -r trigger6-overlay
```

`emerge --sync` then keeps it current alongside `::gentoo`.

## Installing trigger6

The kernel sources of the running kernel must be in `/usr/src/linux` (as for every external module).

```bash
echo 'x11-drivers/trigger6 ~amd64' >> /etc/portage/package.accept_keywords/trigger6-overlay
emerge -av x11-drivers/trigger6
```

If you installed trigger6 by hand before (upstream README sections C and D), remove those files first. The ones
under `/etc` take precedence over the package's copies, and that service file starts the old helper:

```bash
rm /etc/systemd/user/trigger6-fast.service /etc/udev/rules.d/71-trigger6.rules /usr/local/bin/trigger6-fast
udevadm control --reload-rules
```

and, as your desktop user, `systemctl --user daemon-reload`. The ebuild warns about any of these that it finds.

## Runtime notes

* **Module signing:** with `USE=modules-sign` (and `MODULES_SIGN_KEY` / the kernel's signing key set up), the
  module is signed during the build, so kernels that enforce module signatures load it.
* **The helper** (`/usr/bin/trigger6-fast`) loads `libyuv` at run time (`dlopen`), so the dependency on
  `media-libs/libyuv` cannot be seen in its ELF header; without libyuv the driver falls back to its in-kernel
  conversion (about 29 instead of 60 frames per second).
* **Autostart:** the udev rule (`/usr/lib/udev/rules.d/71-trigger6.rules`) gives the logged-in seat user access to
  the adapter and, on systemd, starts the helper as a **user** service (`trigger6-fast.service`) when the adapter
  appears. Without systemd, start `trigger6-fast` in the desktop session yourself.
* **`/etc/modprobe.d/trigger6.conf`** sets `primary_userspace_nv12=1`, so the module hands frames to the helper.
* **Kernel options:** `CONFIG_DRM`, `CONFIG_DRM_KMS_HELPER`, `CONFIG_DRM_GEM_SHMEM_HELPER`, `CONFIG_USB`;
  `CONFIG_SND_PCM` for the HDMI sound card (the display works without it).
* **Xorg:** unplugging the USB adapter crashes the X server (an Xorg bug); Wayland is not affected.

## Upgrading

```bash
emaint sync -r trigger6-overlay
emerge -av x11-drivers/trigger6
```

Then unplug the adapter, run `modprobe -r trigger6` and plug it in again. After a kernel update, rebuild the
module with `emerge -1 @module-rebuild`.

## Bumping the version

New versions come from the release tags of
[trigger6-kernel-module](https://github.com/nvaert1986/trigger6-kernel-module/releases) (skip pre-releases).

```bash
cd x11-drivers/trigger6
git mv trigger6-<old>.ebuild trigger6-<new>.ebuild
ebuild trigger6-<new>.ebuild manifest
```

Re-check on every bump: the files under `packaging/debian13/` that the ebuild installs (udev rule, user service,
`trigger6.conf`), the kernel options in the upstream README's "Requirements", the helper's build command (README
section C) and whether it still only `dlopen`s libyuv.
