class Virtual
  class Host
    include Shortcuts
    attr_reader :virtual, :logger

    def initialize(virtual)
      @virtual = virtual
      @logger  = virtual.logging['host']
    end

    def shell(cmd, options = { })
      logger.debug "shell$ #{cmd}"
      begin
        stdout, stderr = "", ""
        status         = POpen4::popen4(cmd) do |out, err|
          stdout = out.read
          stderr = err.read
        end

        logger.debug stdout.chop if options[:show] == true
        logger.warn stderr.chop if options[:show] == true

        return ShellOutResult.new status.exitstatus == 0, stdout, stderr
      end
    end

    def shell!(cmd, options = { })
      result = shell cmd, options
      raise "cmd failed: #{cmd}\nerr:\n#{result.err}" unless result.success
      result
    end

    def setup_private_network
      out             = shell!("VBoxManage list hostonlyifs").out
      hostonly_config = config.hostonly
      dhcp_config     = hostonly_config.dhcp

      return if out =~ /#{hostonly_config.name}/
      logger.info "Creating hostonly network"

      shell! 'VBoxManage hostonlyif create'
      shell! "VBoxManage hostonlyif ipconfig #{hostonly_config.name} --ip #{hostonly_config.host_ip}"
      shell! "VBoxManage dhcpserver add --ifname #{hostonly_config.name} " +
                 "--ip #{dhcp_config.ip} --netmask #{dhcp_config.mask} " +
                 "--lowerip #{dhcp_config.lower_ip} --upperip #{dhcp_config.upper_ip} " +
                 "--enable"
    end
  end
end