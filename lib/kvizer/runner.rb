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

    attr_reader :sub_commands, :logger

    def initialize()
      @commands = {}
      @cli      = ARGV.clone.join(' ')
      define_commands
      @logger = kvizer.logging['runner']
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

    def die(option_name_or_message, maybe_message = nil)
      option_name, message = if maybe_message
                                 [option_name_or_message, maybe_message]
                               else
                                 [nil, option_name_or_message]
                               end
      logger.error "#{"option: '#{option_name}': " if option_name}#{message}"
      logger.error "Try --help for help."
      exit 1
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
      die "unknown subcommand #{name}" unless @command

      @options = Trollop::options &@command.options
      self
    end

    def run
      kvizer.logger.info @cli
      instance_eval &@command.run
      self
    rescue => e
      notify false
      raise e
    else
      notify true
    end

    private

    def notify(status)
      if kvizer.config.notified_commands.include?(@command.name)
        Notifier.notify :title   => "Kvizer #{status ? 'OK' : 'FAILED'}",
                        :message => "kvizer #{@cli}"
      end
    rescue => e
      kvizer.logger.warn "notification failed: #{e.message} (#{e.class})"
    end

    def get_vm
      kvizer.vm(@options[:vm]).tap { |vm| die :vm, "could not find VM" unless vm }
    end

    def define_commands
      kvizer.config.commands_paths.each do |path|
        path = File.expand_path(path, kvizer.root)
        instance_eval File.read(path), path
      end
    end
  end
end
