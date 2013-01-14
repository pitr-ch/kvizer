class Kvizer
  class ImageBuilder
    include Shortcuts

    attr_reader :kvizer, :vm, :collection, :logger
    def initialize(kvizer, vm, collection)
      @kvizer     = kvizer
      @vm         = vm
      @collection = collection
      @logger     = kvizer.logging["image-base"]
    end

    def rebuild(job_name, last_job = nil, options = { })
      logger.info "rebuilding #{job_name}..#{last_job} with options #{options.inspect}"
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