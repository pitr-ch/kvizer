class Kvizer
  class ImageBuilder < Abstract
    attr_reader :vm, :collection, :logger

    def initialize(kvizer, vm, collection)
      super kvizer
      @vm         = vm
      @collection = collection
      @logger     = logging["image-builder"]
    end

    def rebuild(job_name, last_job = nil, options = {})
      logger.info "rebuilding #{job_name}..#{last_job ? last_job.name : ''} with options #{options.inspect}"
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

      success = job.run vm, options.fetch(job.name.to_sym, {})
      if success
        vm.take_snapshot job.name
        step collection.next_job(job), last_job, options unless job == last_job
      else
        exit 1
      end
    end

  end
end
