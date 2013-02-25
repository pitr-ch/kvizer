class Kvizer
  module Jobs
    class DSL < Abstract
      attr_reader :jobs

      def initialize(kvizer, &definition)
        super kvizer, &nil
        @jobs = {}
        instance_eval &definition
      end

      def job(name, template = nil, &definition)
        raise ArgumentError, "name '#{name}' already taken" if @jobs[name]
        @jobs[name] = if template
                        @jobs[template].clone(name)
                      else
                        Job.new kvizer, name, &definition
                      end
      end
    end
  end
end
