class Kvizer::CLI::Abstract < Clamp::Command
  def self.kvizer_config
    @kvizer_config ||= if superclass.respond_to? :kvizer_config
                         superclass.kvizer_config
                       else
                         Kvizer.load_config
                       end
  end

  def self.vm_name_parameter
    parameter 'VM', 'VM name.', required: true do |v|
      kvizer.vm! v
    end
  end

  def self.new_vm_parameter(default = nil)
    parameter default ? '[NEW_VM]' : 'NEW_VM',
              'Name of new VM',
              default ? { default: default } : {}
  end

  def kvizer
    context[:kvizer] ||= Kvizer.new
  end
end
