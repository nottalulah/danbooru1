unless defined?(RAILS_ROOT)
  root_path = File.join(File.dirname(__FILE__), '..')
# doesn't play nice with symlinks
#  unless RUBY_PLATFORM =~ /mswin32/
#    require 'pathname'
#    root_path = Pathname.new(root_path).cleanpath.to_s
#  end
  RAILS_ROOT = root_path
end

if File.directory?("#{RAILS_ROOT}/vendor/rails")
  require "#{RAILS_ROOT}/vendor/rails/railties/lib/initializer"
else
  require 'rubygems'
  require 'initializer'
end

Rails::Initializer.run(:set_load_path)