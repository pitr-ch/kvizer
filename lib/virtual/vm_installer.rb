class Virtual

  class VmInstaller
    include Shortcuts
    attr_reader :virtual, :vm, :job

    def self.run_job(virtual, vm, job)
      new(virtual, vm, job).run
    end

    def self.run_jobs(virtual, vm, from, to)
      virtual.collections['default'].jobs[from.index..to.index].each do |job|
        run_job(virtual, vm, job)
      end
    end

    def initialize(virtual, vm, job)
      @virtual, @vm, @job = virtual, vm, job
    end

    def run
      virtual.logger.info "Running job '#{job.name}'"
      raise 'system must by stopped' if vm.running?
      restore_snapshots
      run_the_job
      take_snapshot
    end

    def restore_snapshots
      # restore state form previous job
      sleep 5 # FIXME it fails if called right after take
      host.shell! "VBoxManage snapshot \"#{vm.name}\" restore \"#{job.previous.name}\""
      # delete child snapshots
      vm.snapshots.reverse.each do |snapshot|
        if job.me_and_all_next.map(&:name).include? snapshot
          host.shell! "VBoxManage snapshot \"#{vm.name}\" delete \"#{snapshot}\""
        end
      end
    end

    def run_the_job
      job.run(vm)
    end

    #def take_snapshot
    #  cmd = "VBoxManage snapshot \"#{vm.name}\" take \"#{job.name}\""
    #  result = host.shell cmd
    #  if result.success
    #    return
    #  else
    #    sleep 1
    #    host.shell! cmd
    #  end
    #
    #end

  end

end
