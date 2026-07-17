---
name: arklinux-release-custody
description: Preserve a verified ARKlinux ISO as a durable release asset, verify the uploaded bytes by downloading and rehashing them, record provenance, and establish independent backup custody. Use after a bounded milestone is merged and a physical, permanently accessible copy is required.
compatibility: Requires access to the merged repository commit, tags and releases, the verified ISO and evidence files, sha256sum, and approved cloud or physical backup destinations. Publishing and deletion require explicit authorization.
metadata:
  author: 1TRUE-INC
  version: "1.0.0"
---

# ARKlinux release custody

## Purpose

Create a durable binary distribution record without placing a large generated ISO in ordinary Git object history. Preserve the actual ISO, its cryptographic identity, its source and build evidence, and at least one copy outside GitHub.

## Required inputs

Resolve and verify:

- repository and merged commit;
- version and annotated tag name;
- ISO path and filename;
- expected ISO SHA-256;
- release title and bounded claim;
- evidence files to attach;
- approved backup destinations;
- whether publication is draft or final.

Do not publish from a draft PR head unless the user explicitly authorizes a prerelease and the release is clearly labeled as such.

## Preconditions

1. The source milestone has passed review and has been merged, unless this is explicitly a prerelease.
2. The local or downloaded ISO matches the expected SHA-256.
3. The version is not already bound to different bytes.
4. Release notes accurately state what was and was not verified.
5. Required compact evidence exists and is internally consistent.

## Workflow

1. Record the repository, merged commit, source PR, CI run, artifact ID, ISO filename, size, and expected hash.
2. Verify the ISO locally with `sha256sum` before upload.
3. Create or verify an annotated tag at the intended commit.
4. Create a draft release first.
5. Attach the ISO and required evidence files.
6. Require every asset upload to complete with a non-zero size.
7. Download the release ISO into a fresh location.
8. Recalculate its SHA-256 and compare it with the expected value.
9. Download and inspect the attached checksum and provenance files.
10. Record the release URL, asset identifier, upload time, downloaded hash, and verifier.
11. Copy the untouched ISO and evidence package to at least one independent approved storage destination.
12. Verify the independent copy by hash.
13. Preserve a physical copy on user-controlled storage when requested.
14. Publish the release only after all verification passes and the user authorizes publication.

## Required release assets

At minimum:

- versioned ARKlinux ISO;
- `SHA256SUMS`;
- `SOURCE_SHA256SUMS`;
- resolved `packages.lock`;
- machine-readable test summary;
- `ARTIFACT_PROVENANCE.json`;
- `BUILD_RECORD.md`;
- concise known-limitations record.

## Custody record

The final record must identify:

- repository and release URL;
- tag and commit SHA;
- source PR and workflow run;
- ISO filename, size, and SHA-256;
- release asset ID or immutable locator when available;
- upload verification result;
- independent backup locations without exposing secrets;
- date each backup was hash-verified;
- retention or deletion restrictions.

## Stop conditions

Stop before publication when:

- the ISO hash differs;
- the tag points to the wrong commit;
- an asset is absent, empty, or silently renamed;
- release notes overstate the milestone;
- the version already identifies different bytes;
- the downloaded release asset cannot be reverified;
- no independent custody copy exists when one is required.

Never delete the CI artifact, replace a release asset, move a tag, or remove an independent copy without explicit authorization and a replacement verified first.

## Truth boundary

A durable release proves that the preserved bytes correspond to the recorded hash and commit evidence. It does not upgrade the technical claim. An ISO verified only for QEMU live boot remains a live-boot baseline even when permanently released.
