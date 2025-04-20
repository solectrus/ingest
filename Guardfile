# A sample Guardfile
# More info at https://github.com/guard/guard#readme

## Uncomment and set this to only include directories you want to watch
# directories %w(app lib config test spec features) \
#  .select{|d| Dir.exist?(d) ? d : UI.warning("Directory #{d} does not exist")}

## Note: if you are using the `directories` clause above and you are not
## watching the project directory ('.'), then you will want to move
## the Guardfile to a watched dir and symlink it back, e.g.
#
#  $ mkdir config
#  $ mv Guardfile config/
#  $ ln -s config/Guardfile .
#
# and, you'll have to watch "config/Guardfile" instead of "Guardfile"

# Ignore unneeded folders to prevent high CPU load
# https://stackoverflow.com/a/20543493/57950
ignore([%r{^coverage/}, %r{^\.vscode/}, %r{^\.github/}])

# NOTE: The cmd option is now required due to the increasing number of ways
#       rspec may be run, below are examples of the most common uses.
#  * bundler: 'bundle exec rspec'
#  * bundler binstubs: 'bin/rspec'
#  * spring: 'bin/rspec' (This will use spring if running and you have
#                          installed the spring binstubs per the docs)
#  * zeus: 'zeus rspec' (requires the server to be started separately)
#  * 'just' rspec: 'rspec'

guard :rspec,
      cmd: 'bin/rspec --colour --format documentation --fail-fast',
      directories: %w[app spec] do
  # class has changed => run corresponding spec
  watch(%r{^app/(.+)\.rb$})            { |m| "spec/#{m[1]}_spec.rb" }

  # special case for routes
  watch(%r{^app/routes/(.+)\.rb$})     { |m| "spec/routes/#{m[1]}_route_spec.rb" }

  # spec has changed => run it
  watch(%r{^spec/(.+_spec\.rb)$})      { |m| m[0] }

  # spec helper
  watch('spec/spec_helper.rb')         { 'spec' }
end
