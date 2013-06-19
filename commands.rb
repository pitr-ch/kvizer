module Kvizer::CLI
  class List < Abstract
    def execute
      puts kvizer.info.table
    end
  end
  Main.subcommand 'list', 'Displays information about vms.', List

  class Pry < Abstract
    def execute
      kvizer.pry
    end
  end
  Main.subcommand 'pry', 'Run pry session inside Kvizer. Useful for debugging or to run fine grained commands.', Pry

  class Run < Abstract
    vm_name_parameter
    def execute
      vm.run_and_wait
    end
  end
  Main.subcommand 'run', 'Run a virtual machine.', Run

  class Stop < Abstract
    vm_name_parameter
    def execute
      vm.stop_and_wait
    end
  end
  Main.subcommand 'stop', 'Stop a virtual machine.', Stop

  class PowerOff < Abstract
    vm_name_parameter
    def execute
      vm.power_off!
    end
  end
  Main.subcommand 'power-off', 'Power off a virtual machine immediately.', PowerOff

  class Delete < Abstract
    vm_name_parameter
    def execute
      vm.delete
    end
  end
  Main.subcommand 'delete', 'Delete a virtual machine.', Delete

  class Restore < Abstract
    vm_name_parameter
    def execute
      vm.restore_last_snapshot
    end
  end
  Main.subcommand 'restore', 'Restores last snapshot of machine a boots it up (it will turn it off when needed)',
                  Restore

  class SSH < Abstract
    option %w[-u --user], 'LOGIN', 'User login', default: 'user'
    option %w[-t --tunnel], :flag,
           'Creates SSH tunnel to a machine so you can access katello on https://localhost/katello'

    vm_name_parameter

    def execute
      vm.connect user, tunnel?
    end
  end
  Main.subcommand 'ssh', 'SSH an user to a machine. Starts the machine if it`s not running.', SSH


  class Clone < Abstract
    option %w[-t --template], 'TEMPLATE_VM', 'Template VM name.', default: kvizer_config.katello_base do |v|
      kvizer.vm! v
    end

    def default_template
      kvizer.vm! kvizer.config.katello_base
    end

    parameter 'SNAPSHOT', 'Template snapshot name.' do |snapshot|
      template.snapshots.include?(snapshot) or
          raise ArgumentError, "'#{snapshot}' not found between: #{template.snapshots.join(', ')}"
      snapshot
    end

    new_vm_parameter

    def execute
      template.clone_vm(new_vm, snapshot)
    end
  end
  Main.subcommand 'clone', 'Clone a virtual machine.', Clone

  class Build < Abstract
    vm_name_parameter

    option %w[-c --collection], 'COLLECTION', 'Which job collection should be used.', default: :base_jobs do |collection|
      Kvizer::Jobs::Collection.new_by_name kvizer, collection.to_sym
    end

    option %w[-o --options],
           'OPTIONS',
           'Job options string value is evaluated by Ruby to get the Hash.',
           default: {} do |v|
      eval v
    end

    def default_collection
      Kvizer::Jobs::Collection.new_by_name kvizer, :base_jobs
    end

    parameter 'START[..FINISH]', 'Start and finish job to run.', attribute_name: :job_range do |range|
      start, finish = range.split '..'
      [collection[start], (collection[finish] if finish)]
    end

    def execute
      Kvizer::ImageBuilder.new(kvizer, vm, collection).rebuild *job_range, options
    end

  end
  Main.subcommand 'build',
                  "Build a machine by running job collection. It'll run jobs from START to FINISH (or the last one)\n" +
                      "from --collection defined in configuration. It'll create snapshots after each job.",
                  Build

  class BuildBase < Abstract
    option %w[-t --template], 'TEMPLATE_VM', 'Template VM name.', default: 'clean-rhel63' do |v|
      kvizer.vm! v
    end

    def default_template
      kvizer.vm! 'clean-rhel63'
    end

    option %w[-p --product], 'PRODUCT', 'Product to install',
           default: kvizer_config.job_options.send('add-katello-repo').product

    new_vm_parameter "base-#{Time.now.strftime('%y-%m-%d')}"

    def execute
      template.clone_vm(new_vm, 'clean-installation')
      cloned     = kvizer.vm new_vm
      collection = Kvizer::Jobs::Collection.new_by_name kvizer, :base_jobs
      Kvizer::ImageBuilder.new(kvizer, cloned, collection).rebuild collection['base'], nil
    end
  end

  Main.subcommand 'build-base',
                  "Creates base developing machine from vm with clean-installation of a system.\n" +
                      'This image is then used for cloning development machines or to ru ci commands.',
                  BuildBase


  class CI < Abstract
    #option %w[-g --git], 'GIT', 'Url or path to a git repository.',
    #       default: kvizer_config.job_options.package_prepare.source
    option %w[-d --delete], :flag, 'Delete virtual machine first if exists.'
    option %w[-k --koji], :flag, 'Use koji for building rpms.'
    option %w[-e --extra-packages], 'EXTRA',
           "Additional rpms to be downloaded and installed in form of URLs/files, use multiple '-e' specify more rpms.",
           multivalued: true

    option %w[-t --template], 'TEMPLATE_VM', 'Template VM name.', default: kvizer_config.katello_base do |v|
      kvizer.vm! v
    end

    def default_template
      kvizer.vm! kvizer.config.katello_base
    end

    new_vm_parameter "ci-#{Time.now.strftime('%y.%m.%d-%H:%M')}"

    def execute
      vm_to_delete = kvizer.vm(new_vm)
      vm_to_delete.delete if delete? && vm_to_delete

      template.clone_vm new_vm, 'add-katello-repo'
      collection = Kvizer::Jobs::Collection.new_by_name kvizer, :ci_jobs
      Kvizer::ImageBuilder.
          new(kvizer, kvizer.vm(new_vm), collection).
          rebuild kvizer.job_definitions['re-update'], nil,
                  :package_build_rpms => { :use_koji       => koji?,
                                           :extra_packages => extra_packages_list }
    end
  end
  Main.subcommand 'ci',
                  "It will build RPMs (locally or in Koji), install them, run katello-configuration\n" +
                      "and run system tests. It uses --git to clone a source (from local or remote repository)\n" +
                      'and checkout to a --branch.',
                  CI

  class Execute < Abstract
    option %w[-o --options],
           'OPTIONS',
           'Job options string value is evaluated by Ruby to get the Hash.',
           default: {} do |v|
      eval v
    end


    parameter 'JOB', 'Job name to execute', required: true do |name|
      kvizer.job_definitions[name] or
          raise ArgumentError, "job '#{name}' not recognized, available: #{kvizer.job_definitions.keys.join(', ')}"
    end

    vm_name_parameter

    def execute
      job.run vm, options
    end
  end
  Main.subcommand 'execute', 'Execute single job on a machine without saving snapshot.', Execute

  class Give < Abstract
  end
  Main.subcommand 'give', 'Give me a predefined machine', Give

  class GiveProduction < Abstract
    new_vm_parameter
    def execute
      kvizer.vm!(self.class.kvizer_config.katello_base).clone_vm(new_vm, 'configure-katello')
    end
  end
  Give.subcommand 'production', 'Give a machine with production Katello.', GiveProduction

  class GiveDevelopment < Abstract
    new_vm_parameter
    def execute
      kvizer.vm!(self.class.kvizer_config.katello_base).clone_vm(new_vm, 'configure-katello')
    end
  end
  Give.subcommand 'development', 'Give a machine with development Katello.', GiveDevelopment

  class GiveAMachine < Abstract
    new_vm_parameter
    def execute
      kvizer.vm!(self.class.kvizer_config.katello_base).clone_vm(new_vm, 'add-katello-repo')
    end
  end
  Give.subcommand 'a-machine', 'Give a machine.', GiveAMachine
end
