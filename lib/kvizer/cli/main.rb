module Kvizer::CLI
  class Main < Abstract

    self.description = 'Utility to manage virtual machines for Katello development and CI testing.'

    kvizer_config.commands_paths.each do |path|
      require File.expand_path(path, Kvizer.root)
    end

  end
end
