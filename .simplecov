# Configuration only; coverage tracking is started explicitly via
# `SimpleCov.start` in spec/spec_helper.rb (SimpleCov 1.0+).
#
# The default HTML formatter is enough: since 1.0 it emits coverage.json
# itself, and CI (qlty) reads coverage/.resultset.json, which SimpleCov
# always writes. An extra JSONFormatter would just duplicate that work.
SimpleCov.configure do
  group 'Models', 'app/models'
  group 'Routes', 'app/routes'
  group 'Helpers', 'app/helpers'
  group 'Lib', 'app/lib'
end
