# orb-agent-pro images for hosts without quay.io access

This repository carries NetBox Labs orb-agent-pro container images for `linux/amd64`. Each image is saved as a gzipped docker archive and split into 95 MiB parts, because GitHub rejects files over 100 MiB. Use it on hosts that can reach GitHub but not quay.io.

orb-agent-pro is licensed software from NetBox Labs.

## Images in this repository

Fetched 2026-11-10. Digests and checksums are in [images/MANIFEST.txt](images/MANIFEST.txt).

| Archive | Image | orb-agent | Diode SDK (Python) | nbl-cisco-catalyst-center |
|---|---|---|---|---|
| `orb-agent-pro_latest_amd64.tar.gz` | `quay.io/netboxlabs/orb-agent-pro:latest`, same image as release 1.7.2 | 2.17.0 | 1.14.3 | 2.19.0 |
| `orb-agent-pro_develop_amd64.tar.gz` | `quay.io/netboxlabs/orb-agent-pro:develop`, unreleased build for testing | 2.17.0-5e93056 | 1.14.3 | 2.19.1 |

Use `latest` (1.7.2) unless NetBox Labs asks you to test `develop`.

## Requirements on the target host

- git, Docker and `sha256sum`
- Disk space:
  - The clone takes about 1.7 GB, because git keeps a packed copy next to the checked-out parts.
  - Rejoining an archive needs another 430 MB until `load.sh` deletes it.
  - Each loaded image takes about 1 GB in Docker's storage.

Clone onto a filesystem with enough room, not onto a small `tmpfs` such as `/tmp` on some hosts.

If the host reaches GitHub through a proxy, set it for git first:

```bash
export https_proxy=http://<proxy-host>:<port>
```

## Load an image

```bash
git clone --depth 1 https://github.com/cbeye-netbox/orb-agent.git
cd orb-agent/images
./load.sh orb-agent-pro_latest_amd64.tar.gz
```

`--depth 1` downloads only the current images, not the older ones in the git history.

`load.sh` does the following:
1. Joins the parts in name order.
2. Checks the result against the `.sha256` file, and stops before loading if the checksum does not match.
3. Runs `docker load`.
4. Deletes the rejoined archive.

Run `./load.sh` without arguments to load every image in the folder.

`latest` moves on quay.io, so give the loaded image its release tag:

```bash
docker tag quay.io/netboxlabs/orb-agent-pro:latest quay.io/netboxlabs/orb-agent-pro:1.7.2
docker images quay.io/netboxlabs/orb-agent-pro
```

## Reassemble and load by hand

Without `load.sh`, the steps are:

```bash
cd orb-agent/images
cat orb-agent-pro_latest_amd64.tar.gz.part-* > orb-agent-pro_latest_amd64.tar.gz
sha256sum -c orb-agent-pro_latest_amd64.tar.gz.sha256
docker load -i orb-agent-pro_latest_amd64.tar.gz
rm orb-agent-pro_latest_amd64.tar.gz
```

The shell expands `part-*` in alphabetical order (`aaa`, `aab`, ...), which is the order the parts were written in. `sha256sum -c` must print `OK`. `docker load` reads the gzipped archive directly.

To move the image on to a host without GitHub access, copy the rejoined `.tar.gz` and its `.sha256` file there. Then run the same `sha256sum -c` and `docker load` commands.

## Switch the agent to the new image

Recreate the agent container with the options it runs with today. Change only the image reference to `quay.io/netboxlabs/orb-agent-pro:1.7.2`, and keep the same `agent.yaml`, volumes and environment variables.

- Docker Compose: change the `image:` line, then run `docker compose up -d`.
- `docker run`: stop and remove the old container, then run the same command with the new image.

To see which image a container runs:

```bash
docker inspect <container> --format '{{.Config.Image}}'
```

To check the Diode SDK version in the new container:

```bash
docker exec <container> pip show netboxlabs-diode-sdk
```

It should report 1.14.3 or later. Versions up to 1.14.1 drop TLS when `DIODE_SKIP_TLS_VERIFY` is set. Worker policies such as Catalyst Center then get `404` errors from the Diode server.

## Update the images

You need Docker or Podman, git, and pull access to `quay.io/netboxlabs/orb-agent-pro`. The machine does not have to be amd64: the script pulls the amd64 image whatever the local architecture is.

```bash
docker login quay.io                           # enter the token at the prompt
git clone https://github.com/cbeye-netbox/orb-agent.git
cd orb-agent
scripts/fetch-orb-agent-pro.sh 1.7.2 develop   # tags to publish; default: develop latest
cat images/MANIFEST.txt
git add images
git commit -m "Update orb-agent-pro images: 1.7.2, develop"
git push
```

Then update the table at the top of this README from `images/MANIFEST.txt`.

Prefer a release tag such as `1.7.2` over `latest`. Then the archive name and the loaded image carry the version.

For each tag, the script:
- pulls the image for `linux/amd64`, retrying up to five times;
- checks that the local copy really is `linux/amd64`;
- reads the orb-agent, Diode SDK and Catalyst Center versions;
- saves the image, writes the checksum, splits the archive into 95 MiB parts and deletes the full archive.

At the start of a run it deletes every archive already in `images/`, so pass every tag you want to keep. It writes `images/MANIFEST.txt` and copies `scripts/load-orb-agent-pro.sh` to `images/load.sh`.

| Variable | Default | Purpose |
|---|---|---|
| `PLATFORM` | `linux/amd64` | Platform to pull |
| `OUT_DIR` | `images` | Output folder |
| `CHUNK_SIZE` | `95m` | Part size in `split -b` syntax; keep it under 100 MiB |
| `QUAY_USER`, `QUAY_TOKEN` | unset | If both are set, the script logs in to quay.io itself |

Never commit the quay.io token.

On push, GitHub warns about files over 50 MB. The push still succeeds, because only files over 100 MB are rejected.

Each update adds about 430 MB per image to the git history. A `--depth 1` clone does not download that history. GitHub recommends keeping a repository under 5 GB. When the history gets close to that, replace it with a single commit of the current images, for example by committing them on an orphan branch and force-pushing it as `main`.
