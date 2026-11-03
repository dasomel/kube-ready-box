# Box Distribution

How kube-ready-box ships Vagrant boxes since v0.3.0 (decision D7), and why it left Vagrant Cloud.

## Why Vagrant Cloud is gone

HCP Vagrant (formerly Vagrant Cloud) is shutting down.

| Date | Event |
|---|---|
| 2026-10-01 | New boxes and versions can no longer be created. Our uploads fail with `resource creation is currently disabled`. |
| 2026-11-02 | HCP Vagrant support ends. |
| 2026-12-31 | Operations end. All hosted boxes, including every existing `dasomel/*` version, are deleted. |

Sources: [HCP Vagrant EOL](https://developer.hashicorp.com/hcp/docs/vagrant/hcp-vagrant-eol), [important dates and migration guidance](https://www.hashicorp.com/en/blog/hcp-vagrant-deprecation-important-dates-and-migration-guidance).

Until 2026-12-31 old versions still download from `app.vagrantup.com`. Do not depend on that.

## How it works

| Piece | Location |
|---|---|
| `.box` files | GitHub Release assets: `https://github.com/dasomel/kube-ready-box/releases/download/<tag>/<asset>` |
| Catalog metadata (JSON) | GitHub Pages: `https://dasomel.github.io/kube-ready-box/boxes/<box-name>.json` |
| Pages source directory | `site/boxes/` |

Box names stay `dasomel/<name>`.

Vagrant treats an HTTP URL as a catalog only when the response `Content-Type` is `application/json` (`metadata_url?` in Vagrant 2.4.9 `box_add.rb`). Raw GitHub and Release asset URLs do not qualify, so the catalog lives on Pages and points at the Release assets.

## Using a box

In a Vagrantfile:

```ruby
config.vm.box = "dasomel/ubuntu-24.04-ext4"
config.vm.box_url = "https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json"
```

Or add it directly:

```bash
vagrant box add https://dasomel.github.io/kube-ready-box/boxes/ubuntu-24.04-ext4.json
```

Vagrant verifies the catalog checksum. `vagrant box outdated` and `vagrant box update` work through the catalog.

### Current box set

| Box | Version | Provider (arch) |
|---|---|---|
| `ubuntu-24.04-ext4` | 0.3.1 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
| `ubuntu-24.04-xfs` | 0.3.1 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
| `ubuntu-26.04-ext4` | 0.3.1 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
| `ubuntu-26.04-xfs` | 0.3.1 | `vmware_desktop` (arm64), `virtualbox` (amd64) |
| `rocky-9-ext4` | 0.1.1 | `vmware_desktop` (arm64) |
| `rocky-9-xfs` | 0.1.1 | `vmware_desktop` (arm64) |
| `nixos-kube-ready` | 0.2.2 | `libvirt` (arm64; vagrant-libvirt, or vagrant-qemu) |

Asset names look like `ubuntu-24.04-ext4-vmware_desktop-arm64-0.3.1.box` and
`ubuntu-24.04-ext4-virtualbox-amd64-0.3.1.box`. Vagrant picks the provider and architecture that
match the host from the same catalog version. The Ubuntu 0.3.1 boxes are
assets of the `v0.3.1` release; Rocky 0.1.1 and NixOS 0.2.2 stay assets of `v0.3.0`, and each catalog
keeps pointing at the release that holds its files. The Ubuntu catalogs still list 0.3.0.

Ubuntu versions were reset from 1.1.0 (the last Vagrant Cloud upload, never a GitHub Release
asset) to 0.3.0 (now 0.3.1). Vagrant compares versions numerically, so a machine that still has 1.1.0 keeps
booting it and `vagrant box outdated` reports nothing. Remove it once:
`vagrant box remove dasomel/<box> --box-version 1.1.0`. Rocky and NixOS keep their own version lines.

Not in this release:

- VirtualBox arm64 boxes: SSH cannot be verified on the arm64 build host.
- VMware amd64 boxes: amd64 boxes are built and boot-tested on GitHub's x86 runners
  (`.github/workflows/build-amd64.yml`), which run VirtualBox but not VMware.
- Rocky and NixOS amd64 boxes: no amd64 build path exists for them.

### Behavior change (D5)

The root LV is 16 GiB in the image and grows to the whole disk on first boot (`kube-ready-growroot.service`; evidence in `/etc/vagrant-box/growroot.json`). `/swap.img` was removed.

## Publishing (maintainers)

1. Build and verify the boxes (`docs/DEPLOY_CHECKLIST.md`).
2. Compute the SHA-256 of each final `.box` file.
3. Create the GitHub Release tag (for example `v0.3.0`) and upload each `.box` as a release asset. Do not commit `.box` files.
4. Add each box to its catalog under `site/boxes/`, then verify all catalogs:

   ```bash
   tools/box-catalog.py add --catalog site/boxes/<short>.json --name dasomel/<short> \
     --version X --provider P --arch arm64 --url <asset url> --box <local path> \
     --description "Kubernetes-ready <os> box (arm64, <provider>). MIT License. https://github.com/dasomel/kube-ready-box"
   tools/box-catalog.py verify site/boxes
   ```

   `<short>` is the box name without `dasomel/` (for example `ubuntu-24.04-ext4`). `--box` is the local `.box` file that was uploaded, so the checksum comes from the exact bytes.
5. Merge the `site/boxes/` change to `main`. `.github/workflows/pages.yml` deploys GitHub Pages on a push to `main` under `site/**`.
6. Verify from a clean machine: `curl -sI <catalog URL>` shows `content-type: application/json`, then `vagrant box add <catalog URL>` succeeds.

### Checksum rule

The catalog checksum must be the SHA-256 of the exact bytes attached to the Release. Compute it from the file you upload, after the final build. Never replace an asset, or rebuild a box, under a version that is already published. A new build gets a new version, and the old catalog entry stays. A mismatch makes `vagrant box add` fail for every user.

## Ongoing CVE checks

`.github/workflows/box-cve-scan.yml` scans the shipped boxes every Monday (and on demand). It reads
each `site/boxes/*.json` catalog, downloads the box it points to, checks the SHA-256 and runs Trivy on
the package database extracted from the disk. A CRITICAL or HIGH fixable CVE fails the run: rebuild and
publish a new version. Run the same check locally on Linux with
`tools/box-cve-scan.sh site/boxes/<box>.json <work-dir>` (needs root for loop/LVM mounts).

## Deprecated paths

These target Vagrant Cloud and no longer work for new versions. They are kept unchanged for history. Do not use them.

- `upload-boxes.sh`
- `nixos/upload-nixos.sh`
- `packer/scripts/upload-all.sh`
- The `Publish to Vagrant Cloud` steps in `.github/workflows/build-amd64.yml` and `.github/workflows/build-arm64.yml`
- [VAGRANT_CLOUD.md](VAGRANT_CLOUD.md) and [hcp-credentials.md](hcp-credentials.md)

The path is GitHub Release plus the Pages catalog.
