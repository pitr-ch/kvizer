class Kvizer
  class ImageBuilder < Abstract
    attr_reader :vm, :collection, :logger

    def initialize(kvizer, vm, collection)
      super kvizer
      @vm         = vm
      @collection = collection
      @logger     = logging["image-builder"]
    end

    def rebuild(start_job, last_job = nil, options = {})
      logger.info "rebuilding #{start_job.name}..#{last_job ? last_job.name : ''} with options #{options.inspect}"
      if (previous_job = collection.previous_job(start_job))
        vm.restore_snapshot previous_job.name
      else
        logger.error 'cannot rebuild first job'
        return
      end
      step start_job, last_job, options
    end

    def step(start_job, last_job, options)
      return unless start_job
      logger.info "step #{start_job.name}"

      success = start_job.run vm, options.fetch(start_job.name.to_sym, {})
      if success
        vm.take_snapshot start_job.name
        step collection.next_job(start_job), last_job, options unless start_job == last_job
      else
        exit 1
      end
    end

  end
end
