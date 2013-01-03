require 'trollop'
require 'rainbow'

class Kvizer
  class Runner

    class Command
      attr_reader :name
      def initialize(name, &define)
        @name = name
        instance_eval &define
      end

      def options &define
        define ? @options = define : @options
      end

      def run &define
        define ? @run = define : @run
      end
    end

    attr_reader :sub_commands

    def initialize()
      @commands = { }
      define_commands
    end

    def command name, &define
      @commands[name] = Command.new name, &define
    end

    def kvizer
      @kvizer ||= Kvizer.new
    end

    def shift
      ARGV.shift
    end

    def parse
      sub_commands    = @commands.keys
      @global_options = Trollop::options do
        banner "Utility to manage virtual machines for Katello development"
        banner "Subcommands are: \n  #{sub_commands.join("\n  ")}"
        banner "To show help of a subcommand use: kvizer <subcommand> --help "
        stop_on sub_commands
      end

      @command = @commands[name = shift] # get the subcommand
      Trollop::die "unknown subcommand #{name}" unless @command

      @options = Trollop::options &@command.options
      self
    end

    def run
      instance_eval &@command.run
      self
    end

    private

    def get_vm
      kvizer.vm(@options[:vm]).tap { |vm| Trollop::die :vm, "could not find VM" unless vm }
    end

    def define_commands
      kvizer.config.commands_paths.each do |path|
        path = File.expand_path(path, kvizer.root)
        instance_eval File.read(path), path
      end
    end
  end
end
