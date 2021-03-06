require 'socket'
require 'timeout'

class Kvizer
  class VM < Abstract
    class LinePrinter
      def initialize(&printer)
        @printer = printer
        @rest    = ""
      end

      def <<(data)
        @rest << data
        while (line = @rest[/\A.*\n/])
          @printer.call line.chomp
          @rest[/\A.*\n/] = ''
        end
      end
    end

    attr_reader :name, :logger

    def initialize(kvizer, name)
      super kvizer
      @name            = name
      @logger          = logging[name]
      @ssh_connections = {}
    end

    # long hostname breaks CLI tests
    def safe_name
      safe = name.gsub(/[^-a-zA-Z0-9.]/, '-')[0..27]
      safe[-1..-1] != '-' ? safe : safe[0..-2]
    end

    def ip
      kvizer.info.attributes[name][:ip]
    end

    def mac
      kvizer.info.attributes[name][:mac]
    end

    def guest_os
      kvizer.info.attributes[name][:guest_os]
    end

    def fedora?
      guest_os =~ /Fedora/
    end

    def rhel?
      guest_os =~ /Red Hat/
    end

    def shell(user, cmd, options = {})
      logger.info "sh@#{user}$ #{cmd}"

      stdout_data   = ""
      stderr_data   = ""
      exit_code     = nil
      exit_signal   = nil
      final_success = nil
      ssh           = ssh_connection user, options[:password]

      ssh.open_channel do |channel|
        channel.exec(cmd) do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success

          debug = LinePrinter.new { |line| logger.debug line }
          warn  = LinePrinter.new { |line| logger.warn line }

          channel.on_data do |ch, data|
            stdout_data << data
            debug << data
            #$stdout << data
          end
          channel.on_extended_data do |ch, type, data|
            stderr_data << data
            warn << data
            #$stderr << data
          end
          channel.on_request("exit-status") do |ch, data|
            exit_code     = data.read_long
            final_success = exit_code == 0
          end
          channel.on_request("exit-signal") { |ch, data| exit_signal = data.read_long }
        end
      end
      ssh.loop

      logger.warn "'#{cmd}' failed" unless options[:no_warn] || final_success

      return ShellOutResult.new(final_success, stdout_data, stderr_data)
    end

    def shell!(user, cmd, options = {})
      result = shell user, cmd, options
      raise CommandFailed, "cmd failed: #{cmd}" unless result.success
      result
    end

    def ssh_connection(user, password = nil)
      @ssh_connections[user] ||= session = begin
        logger.debug "SSH connecting #{user}"
        Net::SSH.start(ip, user, :password => password, :paranoid => false)
      end
    end

    def ssh_close # TODO collect and close all ssh connections
      @ssh_connections.keys.each do |user|
        ssh = @ssh_connections.delete user
        ssh.close unless ssh.closed?
      end
    end

    def running?
      status == :running
    end

    def wait_for(status, timeout = nil, interval = 5)
      start = Time.now
      loop do
        kvizer.info.reload_attributes
        current = self.status
        return true if current == status
        logger.info "Waiting for: #{status}, now is: #{current}"

        if timeout && timeout < (Time.now - start)
          logger.warn 'Timeout expired.'
          return false
        end

        sleep interval
      end
    end

    def clone_vm(name, snapshot)
      host.shell! "VBoxManage clonevm \"#{self.name}\" --snapshot \"#{snapshot}\" --mode machine " +
                      "--options link --name \"#{name}\" --register"
      kvizer.info.reload
      kvizer.vms(true)
      cloned_vm = kvizer.vm name
      cloned_vm.take_snapshot snapshot
    end

    def delete
      power_off! if running?
      host.shell! "VBoxManage unregistervm \"#{name}\" --delete"
      kvizer.info.reload
      kvizer.vms(true)
    end

    def set_hostname
      raise unless running?
      shell 'root', "hostname #{safe_name}.mydomain"
      shell 'root', "echo 127.0.0.1 #{safe_name} #{safe_name}.mydomain >> /etc/hosts"
    rescue => e
      logger.warn "hostname setting failed: #{e.message} (#{e.class})"
      e.backtrace.each { |l| logger.warn '  %s' % l }
    end

    def status_of_ssh
      timeout(5) { TCPSocket.open(ip, 22).close || true }
    rescue Timeout::Error
      false
    rescue Errno::ECONNREFUSED
      false
    end

    def status
      result     = host.shell!('VBoxManage list runningvms').out
      box_status = !!(result =~ /"#{name}"/)
      if ip
        ping_status = host.shell("ping -c 1 -W 5 #{ip}").success
        ssh_status  = status_of_ssh
      else
        ping_status = ssh_status = false
      end

      case [box_status, ping_status, ssh_status]
      when [false, false, false]
        :stopped
      when [true, false, false]
        :no_connection
      when [true, true, false]
        :no_ssh_running
      when [true, true, true]
        :running
      else
        :unknown
      end
    end

    # TODO add class for snapshot
    def snapshots
      out = host.shell!("VBoxManage snapshot \"#{name}\" list").out
      out.each_line.map do |line|
        line =~ /Name: ([^(]+) \(/
        $1
      end
    end

    def take_snapshot(snapshot_name)
      stop_and_wait
      cmd    = "VBoxManage snapshot \"#{name}\" take \"#{snapshot_name}\""
      result = host.shell cmd
      if result.success
        return
      else
        sleep 1
        host.shell! cmd
      end
      sleep 5 # other commands fail after this when called immidietly
    end

    def restore_snapshot(snapshot_name)
      raise ArgumentError, "No snapshot named #{snapshot_name}" unless snapshots.include? snapshot_name
      power_off! if running?
      # restore state form previous job
      host.shell! "VBoxManage snapshot \"#{name}\" restore \"#{snapshot_name}\""
      # delete child snapshots
      snapshots.reverse.each do |snapshot|
        break if snapshot == snapshot_name
        delete_snapshot snapshot
      end
    end

    def restore_last_snapshot
      restore_snapshot(snapshots.last)
    end

    def delete_snapshot(snapshot_name)
      sleep 1
      host.shell! "VBoxManage snapshot \"#{name}\" delete \"#{snapshot_name}\""
    end

    def run_and_wait(headless = config.headless)
      run headless
      wait_for :running
      set_hostname
      sleep 5 # give the machine time to start fully
    end

    def stop_and_wait
      stop
      wait_for(:stopped, 10*60) || power_off!
    end

    def power_off!
      ssh_close
      host.shell! "VBoxManage controlvm \"#{name}\" poweroff"
      sleep 1
    end

    def connect(user, ssh_tunnel = false)
      run_and_wait

      ssh_command               = "#{'sudo ' if ssh_tunnel}ssh #{user}@#{ip}"
      tunnel_option             = '-L 443:localhost:443'
      ignore_known_host_options = '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

      cmd = [ssh_command, (tunnel_option if ssh_tunnel), ignore_known_host_options].compact.join(' ')

      logger.info "connecting: #{cmd}"
      logger.info "creating ssh tunnel, logout will destroy the tunnel" if ssh_tunnel
      exec cmd
    end

    def to_s
      "#<Kvizer::VM #{name} ip:#{ip.inspect} mac:#{mac.inspect}>"
    end

    def setup_private_network
      raise if running?
      unless mac
        logger.info "Setting up network"
        host.shell! "VBoxManage modifyvm \"#{name}\" --nic2 hostonly --hostonlyadapter2 #{config.hostonly.name}"
        kvizer.info.reload
      else
        true
      end
    end

    def setup_nat_network
      raise if running?
      # use host's resolver, see http://www.virtualbox.org/manual/ch09.html#nat-adv-dns
      # fixes url resolving when connected to VPN
      host.shell! %(VBoxManage modifyvm "#{name}" --natdnshostresolver1 on)
    end

    def setup_resources(ram_megabytes, cpus)
      raise if running?
      host.shell! "VBoxManage modifyvm \"#{name}\" --cpus #{cpus} --memory #{ram_megabytes}"
    end

    def setup_shared_folders
      raise if running?
      config.shared_folders.each do |name, path|
        path = File.expand_path path, kvizer.root
        host.shell "VBoxManage sharedfolder remove \"#{self.name}\" --name \"#{name}\""
        host.shell! "VBoxManage sharedfolder add \"#{self.name}\" --name \"#{name}\" --hostpath \"#{path}\" " +
                        "--automount"
      end
    end

    private

    def run(headless = config.headless)
      unless running?
        setup_shared_folders
        host.shell! "VBoxManage startvm \"#{name}\" --type #{headless ? 'headless' : 'gui' }"
      end
    end

    def stop
      unless status == :stopped
        ssh_close
        host.shell! "VBoxManage controlvm \"#{name}\" acpipowerbutton"
      end
    end

    #def mount_point_path
    #  @mount_point_path ||= File.join(config.vbox.mount_dir, name)
    #end

    #def mount
    #  Dir.mkdir mount_point_path unless File.exist? mount_point_path
    #  unless mounted?
    #    result = host.shell! "sshfs #{user}@#{ip}:/ #{mount_point_path}"
    #    raise result.err unless result.success
    #    File.symlink mount_point_path, link_path unless File.exist?(link_path)
    #  else
    #    logger.error "already mounted"
    #  end
    #  self
    #end
    #
    #def unmount
    #  if mounted?
    #    result = host.shell! "umount #{mount_point_path}"
    #    raise result.err unless result.success
    #    File.delete link_path if File.exist?(link_path)
    #  else
    #    logger.error "not mounted"
    #  end
    #  self
    #end
    #
    #def mounted?
    #  Dir.glob(File.join(mount_point_path, '**')).size > 2
    #end

    #def user
    #  if name =~ /fedora/
    #    config.users.fedore
    #  elsif name =~ /rhel/
    #    config.users.rhel
    #  else
    #    raise
    #  end
    #end
    #

    #def link_path
    #  "/Users/pitr/#{name}"
    #end
  end
end
