<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. The release skill takes this file and empties it again.

What goes in: a change an operator or a writing client can see or feel. Not
dependency bumps, refactorings, tests, CI, lint fixes. If the change is reverted
before the release, delete the line.

How to write it: one line, English, the words of the API and the README. Name
what changed for the reader, not how it was built. Add "(#358)" when an issue or
a discussion drove the change. Under "Fixes", write what works now, never what
was broken.

Keep every section, an empty one included.
-->

## New features

- Write endpoint: a request body that carries `Content-Encoding: gzip` is unzipped now, so a client such as the InfluxDB client for JavaScript can write compressed data. A body that expands above 8 MB gets 413 and is not stored.
- Query endpoint: `/api/v2/query` answers 403 instead of 404. A client that asks for the field types of a bucket before its first write, such as the SOLECTRUS integration for Home Assistant, reads that as a token without read permission and finishes its setup.

## Improvements

## Fixes

## Maintenance

- Dependencies updated
