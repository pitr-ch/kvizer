class Virtual
  class ImageBuilder
    include Shortcuts

    attr_reader :virtual, :vm, :collection, :logger
    def initialize(virtual, vm, collection)
      @virtual    = virtual
      @vm         = vm
      @collection = collection
      @logger     = virtual.logging["image-base"]
    end

    def rebuild(job_name, last_job = nil, options = { })
      logger.info "rebuilding #{job_name}"
      job      = collection[job_name]
      previous = collection.previous_job(job)
      if previous
        vm.restore_snapshot previous.name
      else
        logger.error "cannot rebuild first job"
        return
      end
      step job, last_job, options
    end

    def step(job, last_job, options)
      return unless job
      logger.info "step #{job.name}"

      vm.run_job job, options.fetch(job.name.to_sym, { })

      vm.take_snapshot job.name
      step collection.next_job(job), last_job, options unless job == last_job
    end

  end
end