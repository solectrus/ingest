# Configuration only; coverage tracking is started explicitly via
# `SimpleCov.start` in spec/spec_helper.rb (SimpleCov 1.0+).
#
# The default HTML formatter is enough: since 1.0 it emits coverage.json
# itself, and CI (qlty) reads coverage/.resultset.json, which SimpleCov
# always writes. An extra JSONFormatter would just duplicate that work.

# Branch coverage on top of line coverage: a guard clause like `return if x`
# runs its line in both cases, so lines alone cannot show that only one of
# them is tested.
SimpleCov.enable_coverage :branch

# Both stand at 100, and CI holds them there: a run that leaves a line or a
# branch untested exits non-zero, so the build refuses the change instead of
# letting the number drift down one commit at a time.
#
# A branch that no test can reach carries `# simplecov:disable branch` and the
# reason for it. The threshold thus turns every gap into a decision that the
# diff shows.
#
# CI alone, because the threshold measures the whole suite. Guard runs the one
# file that changed, see the Guardfile, and every other file of the project is
# then untested by definition.
SimpleCov.minimum_coverage(line: 100, branch: 100) if ENV['CI']

# Migrations stay out of the number, for two reasons.
#
# They run once against a real database, and a test database cannot hold the
# state that some of them repair: the dedup of AddUniqueIndexToTargets needs
# duplicate rows, and a fresh schema has none. `down` never runs either.
#
# And their coverage depends on whether data/test.sqlite3 exists. A database
# that already holds the schema runs no migration, so the files never load and
# never count. The same suite thus reports a different number on a developer
# machine than on CI, and a threshold on that number guards nothing.
SimpleCov.add_filter 'db/migrate'

SimpleCov.configure do
  group 'Models', 'app/models'
  group 'Routes', 'app/routes'
  group 'Helpers', 'app/helpers'
  group 'Lib', 'app/lib'
end
