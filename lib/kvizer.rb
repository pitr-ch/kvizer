require 'bundler/setup'

require 'popen4'
require 'pp'
require 'log4r'
require 'net/ssh'
require 'pry'
require 'notifier'

lib_path = File.expand_path(File.join(File.dirname(__FILE__)))
$: << lib_path unless $:.include? lib_path


class Kvizer
  class ShellOutResult < Struct.new(:success, :out, :err)
    alias_method :success?, :success
  end

  class CommandFailed < StandardError
  end

  require 'kvizer/abstract'
  require 'kvizer/config_node'
  require 'kvizer/vm'
  require 'kvizer/info_parser'
  require 'kvizer/host'
  require 'kvizer/logging'
  require 'kvizer/jobs'
  require 'kvizer/image_builder'

  def self.load_config
    ConfigNode.new(YAML.load_file("#{root}/config.yml")).tap do |config|
      config.deep_merge! YAML.load_file(File.expand_path(config.config_override, root)) if config.config_override
    end
  end

  attr_reader :logger, :host, :logging, :config

  def initialize(config = self.class.load_config)
    @config  = config
    @logging = Logging.new(self)
    @logger  = logging['kvizer']
    @host    = Host.new(self)
  end

  def vm(part_name)
    vms.find { |vm| vm.name == part_name } || begin
      regexp     = part_name.kind_of?(String) ? /#{part_name}/ : part_name
      candidates = vms.select { |vm| vm.name =~ regexp }
      raise ArgumentError, "ambiguous vm name '#{part_name}' candidates: #{candidates.map(&:name).join ', '}" if candidates.size > 1
      candidates.first
    end
  end

  def info
    @info ||= InfoParser.new(self)
  end

  def vm!(part_name)
    vm part_name or raise ArgumentError, "vm with name '#{part_name}' was not found"
  end

  def vms(reload = false)
    @vms = nil if reload
    @vms ||= info.attributes.map { |name, _| VM.new(self, name) }
  end

  def to_s
    "Kvizer[#{vms.map(&:to_s).join(', ')}]"
  end

  def self.root
    @root ||= File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  def root
    self.class.root
  end

  def job_definitions
    me = self

    @jobs_definitions ||= Jobs::DSL.new self do
      me.config.jobs_paths.each do |path|
        path = File.expand_path(path, me.root)
        instance_eval File.read(path), path
      end
    end.jobs
  end
end
