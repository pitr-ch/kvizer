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
      @cli = ARGV.clone.join(' ')
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
      commands      = @commands
      sub_commands  = @commands.keys
      global_parser = Trollop::Parser.new do
        banner "Utility to manage virtual machines for Katello development"
        banner "Subcommands are: #{sub_commands.join(", ")}. See bellow."
        banner "To show help of a subcommand use: kvizer <subcommand> --help "
        stop_on sub_commands
      end

      original_educate = global_parser.method(:educate)
      global_parser.singleton_class.send :define_method, :educate do
        original_educate.call

        commands.each do |key, command|
          puts
          puts "== kvizer #{key} <options>".bright
          Trollop::Parser.new(&command.options).educate
        end
      end

      @global_options = Trollop::with_standard_exception_handling global_parser do
        raise Trollop::HelpNeeded if ARGV.empty? # show help screen
        global_parser.parse ARGV
      end

      @command = @commands[name = shift] # get the subcommand
      Trollop::die "unknown subcommand #{name}" unless @command

      @options = Trollop::options &@command.options
      self
    end

    def run
      kvizer.logger.info @cli
      instance_eval &@command.run
      if kvizer.config.notified_commands.include?(@command.name)
        Notifier.notify :title => "Kvizer status",
                        :message => "Kvizer command '#{$0} #{@cli}' finished"
      end
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
