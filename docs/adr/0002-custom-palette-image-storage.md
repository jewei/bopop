# ADR 0002: Store an imported palette image as the state flag

- Status: accepted
- Date: 2026-07-20

## Context

Users can replace the palette header keycap with an image. Referencing an
arbitrary source file would require persistent file access and leave behavior
dependent on moves, permissions, and later edits. A separate preference flag
could also disagree with the stored image.

## Decision

Import, decode, aspect-fill crop, and downscale the chosen image to a 128 × 128
PNG at `Storage.brandImageURL` (`brand.png`, mode `0600`). The original is not
referenced again. Presence of that file is the only “custom image active” flag;
reset deletes it. A missing or undecodable image falls back to the drawn keycap.
The application checks the file when showing the palette so a Settings change
applies on the next summon.

The application target owns image decoding because it requires AppKit.
`BopopKit.Storage` owns only the well-known URL under its base directory.

## Consequences

The feature needs no security-scoped bookmark or duplicate defaults state. The
user's original image remains untouched. Image import and fallback behavior
remain part of manual release QA until the application target has a faithful
test seam.
