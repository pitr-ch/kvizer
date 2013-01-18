# TODO remove die form these helper methods

def self.rebuild(vm_name, start_job_name, finish_job_name, collection_name = :base_jobs, job_options = { })
  collection = Kvizer::Jobs::Collection.new_by_names kvizer, *kvizer.config.send(collection_name)
  job = collection[start_job_name] rescue Trollop::die(:job, "could not find job with name '#{start_job_name}'")

  last_job = collection[finish_job_name] rescue nil
  if last_job.nil? && finish_job_name
    Trollop::die(:finish_job, "could not find job with name'#{finish_job_name}'")
  end

  kb = Kvizer::ImageBuilder.new kvizer, kvizer.vm(vm_name), collection
  kb.rebuild job.name, last_job, job_options
end

def self.clone_vm(vm, name, snapshot)
  Trollop.die :name, "is required, was '#{name}'" if name.nil? || name.empty?
  Trollop.die :snapshot, "could not find snapshot #{snapshot}" unless vm.snapshots.include?(snapshot)

  vm.clone_vm(name, snapshot)
end

vm_option = lambda do |o, description = nil, default = nil|
  options = { :short => "-m", :type => :string }
  options.merge! :default => default if default
  options.merge! :required => true unless default

  o.opt :vm, description || 'Virtual Machine name', options
end

kvizer = self.kvizer

command 'info' do
  options { banner 'Displays information about vms.' }
  run { puts kvizer.info.table }
end

command 'pry' do
  options { banner 'Run pry session inside Kvizer. Useful for debugging or to run fine grained commands.' }
  run { kvizer.pry }
end

command 'run' do
  options do
    banner 'Run a virtual machine.'
    vm_option.call self
  end
  run { get_vm.run_and_wait }
end

command 'stop' do
  options do
    banner 'Stop a virtual machine.'
    vm_option.call self
  end
  run { get_vm.stop_and_wait }
end

command 'delete' do
  options do
    banner 'Delete a virtual machine.'
    vm_option.call self
  end
  run do
    vm = get_vm
    vm.power_off! if vm.running?
    vm.delete
  end
end

command 'power-off' do
  options do
    banner 'Power off a virtual machine immediately.'
    vm_option.call self
  end
  run { get_vm.power_off! }
end

command 'ssh' do
  options do
    banner 'SSH an user to a machine. Starts the machine if it`s not running.'
    opt :user, "User login", :short => "-u", :type => :string, :default => 'user'
    vm_option.call self
  end
  run do
    Trollop::die :user, "user is required" unless @options[:user]
    get_vm.connect(@options[:user])
  end
end

command 'clone' do
  options do
    banner 'Clone a virtual machine.'
    opt :name, "Name of the new machine", :short => '-n', :type => :string, :required => true
    opt :snapshot, "Name of a source snapshot", :short => '-s', :type => :string, :required => true
    vm_option.call self, nil, kvizer.config.katello_base
  end
  run { clone_vm get_vm, @options[:name], @options[:snapshot] }
end

command 'build' do
  options do
    banner "Build a machine by running job collection. It'll run jobs from --start_job to --finish_job " +
               "(or the last one of option is not supplied) from --collection defined in configuration. " +
               "'It'll create snapshots after each job."
    opt :start_job, 'Starting job name', :short => '-s', :type => :string, :required => true
    vm_option.call self, 'Run build on a machine with this name', kvizer.config.katello_base
    opt :finish_job, 'Finish job name', :short => '-f', :type => :string
    opt :collection, 'Which job collection should be used',
        :short => '-c', :type => :string, :default => 'base_jobs'
    opt :options, 'Job options string value is evaluated by Ruby to get the Hash',
        :short => '-o', :type => :string
  end
  run do
    rebuild @options[:vm], @options[:start_job], @options[:finish_job], @options[:collection].to_sym,
            @options[:options] ? eval(@options[:options]) : { }
  end
end

command 'build-base' do
  options do
    banner "Creates base developing machine from vm with clean installation of a system. This image is then used" +
               "for cloning development machines or to ru ci commands."
    vm_option.call self, 'Name of a clean installation'
    opt :name, "Name of the new machine", :short => '-n', :type => :string, :required => true
    opt :product, "Product to install ", :short => '-p', :type => :string,
        :required => false, :default => kvizer.config.job_options.send('install-katello').product
  end
  run do
    clone_vm(get_vm, @options[:name], 'clean installation')
    rebuild @options[:name], 'base', nil, :base_jobs,
            :"install-katello" => { :product => @options[:product] }
  end
end

command 'execute' do
  options do
    banner 'Execute single job on a machine without saving snapshot.'
    opt :job, 'Job name', :short => '-j', :type => :string, :required => true
    opt :options, 'Job options string value is evaluated by Ruby to get the Hash',
        :short => '-o', :type => :string
    vm_option.call self
  end
  run do
    job = kvizer.job_definitions[@options[:job]]
    unless job
      Trollop.die :job, "'#{@options[:job]}' could not find a job, avaliable:\n  " +
          "#{kvizer.job_definitions.keys.join("\n  ")}"
    end
    get_vm.run_job job, @options[:options] ? eval(@options[:options]) : { }
  end
end

command 'ci' do
  options do
    banner 'It will build RPMs (locally or in Koji), install them, run katello-configuration and run system tests. ' +
               'It uses --git to clone a source (from local or remote repository) and swithes to a --branch.'
    opt :git, "url/path to git repository",
        :short => '-g', :type => :string, :default => kvizer.config.job_options.package2.source
    opt :branch, "branch to checkout",
        :short => '-b', :type => :string, :default => kvizer.config.job_options.package2.branch
    opt :name, "Machine name", :short => '-n', :type => :string
    opt :base, "Base for cloning", :type => :string, :default => kvizer.config.katello_base
    opt :use_koji, "Use koji for building rpms"
  end
  run do
    branch  = @options[:branch] || kvizer.config.job_options.package2.branch
    vm_name = @options[:name] || "ci-#{branch}"
    clone_vm kvizer.vm(@options[:base]), vm_name, 'install-packaging'
    rebuild vm_name, 'package2', 'system-test', :build_jobs,
            :package2 => { :source => @options[:git], :branch => branch, :use_koji => @options[:use_koji] }
  end
end
