---
layout: default
title: "Versioning and Support"
permalink: /docs/VERSIONING
---

# Versioning and Support

What you can expect from a RED release. This covers the [Public API](PUBLIC_API.md). Anything not on
that page is private and can change in any release.

## Versioning

RED follows Semantic Versioning (SemVer) from 1.0.0. A minor release is safe to take with
`bundle update` on `~> 1.0`.

## Deprecations

A deprecation warns for at least two minor releases, and the deprecated thing is removed only in a
major. The last minor before a major warns about everything that major removes.

## Rails and Ruby versions

Rails and Ruby minimums rise only at a major.

## Migrations

Migrations in a minor are additive and safe to run twice.

## Security fixes

Security fixes go to the current major, and to the previous major's last minor.

## 0.x support

RED 1.0 requires Rails 7.2 and Ruby 3.3. Until then, 0.x keeps working on the older versions it
supports today, and logs a warning at boot if you're on one.

After 1.0 ships, 0.x gets security fixes only, on its last minor, until 2027-06-30.
