require 'bundler/setup'

require 'popen4'
require 'pp'
require 'log4r'
require 'net/ssh'
require 'pry'
require 'active_support/inflector'

lib_path = File.expand_path(File.join(File.dirname(__FILE__)))
$: << lib_path unless $:.include? lib_path


class Virtual
  ShellOutResult = Struct.new(:success, :out, :err)
  class CommandFailed < StandardError
  end

  require 'virtual/shortcuts'
  require 'virtual/config'
  require 'virtual/vm'
  require 'virtual/info_parser'
  require 'virtual/host'
  require 'virtual/logging'
  require 'virtual/jobs'
  require 'virtual/image_base'

  attr_reader :logger, :info, :host, :logging

  def initialize
    @logging = Logging.new(self)
    @logger  = logging['virtual']
    @host    = Host.new(self)

    @info = InfoParser.new(self)
  end

  def vm(part_name)
    regexp = part_name.kind_of?(String) ? /#{part_name}/ : part_name
    vms.select { |vm| vm.name =~ regexp }.
        tap { |arr| raise "ambiguous vm name #{part_name}" if arr.size > 1 }.
        first
  end

  def vm!(part_name)
    vm part_name or raise ArgumentError, "vm with name '#{part_name}' was not found"
  end

  def vms(reload = false)
    @vms = nil if reload
    @vms ||= info.attributes.map { |name, _| VM.new(self, name) }
  end

  def setup_development_vms
    # TODO add machine to host
    config.development_vms.each do |name, config|
      if clone = vm(name) rescue nil
        clone.delete
      end
      vm(config.template).clone_vm(name, config.snapshot)
    end
  end

  def to_s
    "Virtual[#{vms.map(&:to_s).join(', ')}]"
  end

  def root
    @root ||= File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  def job_definitions
    me = self

    @jobs_definitions ||= Jobs2::DSL.new self do
      path = "#{me.root}/jobs.rb"
      instance_eval File.read(path), path
    end.jobs
  end


end