require 'trollop'

class Virtual
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

    def virtual
      @virtual ||= Virtual.new
    end

    def shift
      ARGV.shift
    end

    def parse
      sub_commands    = @commands.keys
      @global_options = Trollop::options do
        banner "Utility to manage virtual machines for Katello development"
        banner "Subcommands are: #{sub_commands.join(' ')}"
        banner "To show help of a subcommand use: virtual <subcommand> --help "
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
      virtual.vm(@options[:vm]).tap { |vm| Trollop::die :vm, "could not find VM" unless vm }
    end

    def define_commands
      vm_option = lambda { |o| o.opt :vm, "Virtual Machine name", :short => "-m", :type => String }
      virtual   = self.virtual

      command 'info' do
        options { banner 'Displays information about vms.' }
        run { puts virtual.info.attributes.to_yaml }
      end

      command 'pry' do
        options { banner 'Run pry session.' }
        run { virtual.pry }
      end

      command 'run' do
        options do
          banner 'Run a virtual machine.'
          vm_option.call self
        end
        run { get_vm.run }
      end

      command 'stop' do
        options do
          banner 'Stop a virtual machine.'
          vm_option.call self
        end
        run { get_vm.stop }
      end

      command 'power-off' do
        options do
          banner 'Power off a virtual machine.'
          vm_option.call self
        end
        run { get_vm.power_off! }
      end

      command 'ssh' do
        options do
          banner 'SSH an user to a machine.'
          opt :user, "User login", :short => "-u", :type => String, :default => 'user'
          vm_option.call self
        end
        run do
          Trollop::die :user, "user is required" unless @options[:user]
          get_vm.connect(@options[:user])
        end
      end

      command 'execute' do
        options do
          banner 'Rebuild base machine.'
          opt :start_job, "Starting job name", :short => "-s", :type => String
          opt :vm, "Virtual Machine name", :short => "-m", :type => String, :default => virtual.config.katello_base
          opt :finish_job, "Finish job name", :short => '-f', :type => String
          opt :collection, "Which job collection should be used", :short => '-c', :type => String
        end
        run do
          collection_name = @options[:collection] ? @options[:collection].to_sym : :base_job
          rebuild @options[:vm], @options[:start_job], @options[:finish_job], collection_name
        end
      end

      command 'clone' do
        options do
          banner 'Clone a virtual machine'
          opt :name, "Name of the new machine", :short => '-n', :type => String
          opt :snapshot, "Name of a source snapshot", :short => '-s', :type => String
          vm_option.call self
        end
        run { clone_vm get_vm, @options[:name], @options[:snapshot] }
      end

      command 'ci' do
        options do
          banner 'From a git repository: build rpms, install them, run katello-configuration and run system tests'
          opt :git, "url/path to git repository", :short => '-g', :type => String
          opt :branch, "branch to checkout", :short => '-b', :type => String
          opt :name, "Machine name", :short => '-n', :type => String
        end
        run do
          vm_name = @options[:name] || "ci-#{@options[:branch]}"
          clone_vm virtual.vm(virtual.config.katello_base), vm_name, 'install-packaging'
          rebuild vm_name, 'package2', 'system-test', :build_jobs,
                  :package2 => { :source => @options[:git], :branch => @options[:branch] }
        end
      end

    end

    def rebuild(vm_name, start_job_name, finish_job_name, collection_name = :base_jobs, job_options = { })
      collection = Virtual::Jobs2::Collection.new_by_names virtual, *virtual.config.send(collection_name)
      job = collection[start_job_name] rescue Trollop::die(:job, "could not find job with name '#{start_job_name}'")

      last_job = collection[finish_job_name] rescue nil
      if last_job.nil? && finish_job_name
        Trollop::die(:finish_job, "could not find job with name'#{finish_job_name}'")
      end

      kb = Virtual::ImageBase.new virtual, virtual.vm(vm_name), collection
      kb.rebuild job.name, last_job, job_options
    end

    def clone_vm(vm, name, snapshot)
      Trollop.die :name, "is required, was '#{name}'" if name.nil? || name.empty?
      Trollop.die :snapshot, "could not find snapshot #{snapshot}" unless vm.snapshots.include?(snapshot)

      vm.clone_vm(name, snapshot)
    end

  end
end
