# SOLECTRUS Ingest

Plain Ruby service (Sinatra, no Rails) behind the InfluxDB write API. It takes
line protocol, computes the house power and writes the result to InfluxDB.

## Changelog

If an operator or a writing client can see or feel a change, add a line to
`.changelog/unreleased.md` in the same commit. The file carries the rules for
the wording. The release skill turns it into the GitHub release notes and
empties it.

## Mandatory linting

After a change to Ruby code, run `bin/rubocop` and fix what it reports (`-A`
auto-corrects, review the result).

## Testing

`bin/rspec [path]`. `bin/ci` runs the full gate: linter and tests.

## Development

`bin/dev` starts the service, `bin/console` opens a REPL.
