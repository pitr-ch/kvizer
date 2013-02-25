class Kvizer
  class Abstract
    attr_reader :kvizer

    def initialize(kvizer)
      @kvizer = kvizer
    end

    def host
      kvizer.host
    end

    def config
      kvizer.config
    end

    def logging
      kvizer.logging
    end
  end
end