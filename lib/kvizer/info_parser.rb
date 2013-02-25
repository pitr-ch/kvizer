class Kvizer
  class InfoParser < Abstract
    attr_reader :raw_attributes, :attributes

    def initialize(kvizer)
      super kvizer
      reload
    end

    def reload
      input = host.shell!("VBoxManage list vms -l").out

      splitter       = 'Name:            '
      system_strings = input.split(/^#{splitter}/)[1..-1].map { |str| splitter + str }

      reload_raw_attributes system_strings
      reload_attributes

      #kvizer.logger.debug "Attributes:\n" + attributes.pretty_inspect
      self
    end

    def vm_names
      attributes.keys
    end

    def table
      columns   = [-30, 15, 13, 20]
      format    = columns.map { |c| "%#{c}s" }.join('  ') + "\n"
      delimiter = columns.map { |c| '-'*c.abs }.join('  ') + "\n"
      head      = %w(name ip status os)
      data      = attributes.values.map do |attr|
        { :name => attr[:name], :ip => attr[:ip], :status => kvizer.vm(attr[:name]).status, :guest_os => attr[:guest_os] }
      end
      delimiter + format % head + delimiter + data.sort do |a, b|
        [a[:status].to_s, a[:name].to_s] <=> [b[:status].to_s, b[:name].to_s]
      end.map do |attr|
        format % [attr[:name], attr[:ip], attr[:status], attr[:guest_os]]
      end.join + delimiter
    end

    def reload_raw_attributes(system_strings)
      @raw_attributes = system_strings.map do |system_string|
        attribute_string = system_string.split(/\n\n/, 2).first
        attribute_string.each_line.inject({}) do |hash, line|
          line =~ /^([^:]+):\s+(.+)$/
          k, v    = $1, $2
          hash[k] = parse_nic k, v
          hash
        end
      end.inject({}) do |hash, attributes|
        hash[attributes['Name']] = attributes
        hash
      end
    end

    def reload_attributes
      mac_ip_map = get_mac_ip_map

      @attributes = raw_attributes.values.inject({}) do |hash, raw_attributes|
        name       = raw_attributes['Name']
        guest_os   = raw_attributes['Guest OS']
        hash[name] = { :name     => name,
                       :guest_os => guest_os,
                       :mac      => mac = find_mac(raw_attributes, config.hostonly.name),
                       :ip       => mac_ip_map[mac] }
        hash
      end
    end

    def find_mac(raw_attributes, net)
      interface = raw_attributes.find { |k, v| k =~ /NIC \d$/ && v['Attachment'] =~ /#{net}/ }
      normalize_mac interface.last['MAC'] if interface
    end

    def get_mac_ip_map
      result = host.shell(cmd = "sudo arp-scan --interface=#{config.hostonly.name} " +
          "#{config.hostonly.dhcp.lower_ip}-#{config.hostonly.dhcp.upper_ip}")
      return {} unless result.success

      result.out.each_line.inject({}) do |hash, line|
        next hash unless line =~ /^([\d\.]+)\s+([0-9a-f:]+)/
        hash[normalize_mac $2] = $1 if $1
        hash
      end
    end

    def normalize_mac(mac)
      return nil if mac.nil?
      if mac =~ /:/
        mac.split(':').map do |part|
          if part.size == 1
            '0' + part.downcase
          else
            part.downcase
          end
        end
      else
        mac.downcase.each_char.each_slice(2).map { |s| s.join }.to_a
      end.join(':')
    end

    def parse_nic(key, value)
      if key =~ /NIC \d$/
        value.split(/,\s+/).inject({}) do |hash, pair|
          k, v    = pair.split(/:\s+/)
          hash[k] = v
          hash
        end
      else
        value
      end
    end


  end
end