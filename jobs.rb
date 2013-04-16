job 'clean-installation'

job 'base' do
  offline do
    host.setup_private_network
    vm.setup_nat_network
    vm.setup_private_network
  end
  online do
    shell! 'root', 'mkdir -p .ssh', :password => config.root_password
    shell! 'root', %(printf "#{config.authorized_keys}" > .ssh/authorized_keys),
           :password => config.root_password
    shell! 'root', 'chmod 700 .ssh'
    shell! 'root', 'chmod 600 .ssh/authorized_keys'
    shell! 'root', 'restorecon -R -v /root/.ssh' # SELinux evil
  end
end

job 'disable-selinux' do
  online do
    shell 'root', 'sed "s/SELINUX=.*/SELINUX=disabled/" -i /etc/selinux/config'
  end
end

job 'add-katello-repo' do
  online do
    system = case
             when vm.fedora?
               :fedora
             when vm.rhel?
               :rhel
             else
               raise 'unknown distribution, currently only Fedora and RHEL supported'
             end

    url = options[:repositories][system][options[:product].to_sym][options[:version]]
    case options[:product]
    when 'katello'
      shell! 'root', "rpm -Uvh #{url}"
      # shell 'root', 'service iptables stop' # fix for fedora17
      yum_install 'katello-repos-testing' if options[:version] == :latest
    when 'cfse'
      vm.shell! 'root', "yum-config-manager --add-repo  #{url}"
    else
      raise "Unsupported product #{options[:product]}"
    end
  end
end

job 'install-katello' do
  online do
    # shell 'root', 'service iptables stop' # fix for fedora17
    yum_install 'katello-all'
  end
end

job 'configure-katello' do
  online { shell! 'root', 'katello-configure --no-bars --user-pass admin' }
end

job 'turnoff-services' do
  online do
    shell! 'root', 'service iptables stop'
    shell! 'root', 'service katello stop'
    shell! 'root', 'service katello-jobs stop'
    shell! 'root', 'chkconfig iptables off'
    shell! 'root', 'chkconfig katello off'
    shell! 'root', 'chkconfig katello-jobs off'
    # TODO stop foreman
  end
end

job 'add-user' do
  online do
    shell! 'root', 'useradd user -G wheel'
    shell! 'root', 'passwd user -f -u'
    shell! 'root', "echo #{config.user_password} | passwd user --stdin"
    shell! 'root', 'su user -c "mkdir /home/user/.ssh"'
    shell! 'root', 'su user -c "touch /home/user/.ssh/authorized_keys"'
    shell! 'root', 'cat /root/.ssh/authorized_keys > /home/user/.ssh/authorized_keys'

    shell! 'root', 'chmod u+w /etc/sudoers'
    shell! 'root',
           'sed -i -E "s/# %wheel\s+ALL=\(ALL\)\s+NOPASSWD: ALL/%wheel\tALL=\(ALL\)\tNOPASSWD: ALL/" ' +
               '/etc/sudoers'
    shell! 'root',
           'sed -i -E "s/%wheel\s+ALL=\(ALL\)\s+ALL/# %wheel\tALL=\(ALL\)\tALL/" /etc/sudoers'
    shell! 'root',
           'sed -i -E "s/Defaults\s+requiretty/# Defaults\trequiretty/" /etc/sudoers'
    shell! 'root', 'chmod u-w /etc/sudoers'
    shell! 'user', 'sudo echo a' # test
  end
end

job 'install-essentials' do
  online do
    yum_install 'wget'
    yum_install "htop"
    yum_install "multitail"
    yum_install "ack"
    yum_install "vim"
    shell 'root', 'echo "set bg=dark" >> /etc/vimrc'
  end
end

job 'install-guest-additions' do
  online do
    version = config.virtual_box_version
    if vm.rhel?
      shell! 'root', 'rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm'
    end
    yum_install *%w(dkms kernel-devel)
    shell! 'root', 'yum -y groupinstall "Development Tools"'
    shell! 'root',
           "wget http://download.virtualbox.org/virtualbox/#{version}/VBoxGuestAdditions_#{version}.iso"
    shell! 'root', 'mkdir additions'
    shell! 'root', "mount -o loop VBoxGuestAdditions_#{version}.iso ./additions"
    shell! 'root', 'additions/VBoxLinuxAdditions.run'
    shell! 'root', 'usermod -a -G vboxsf root'
    shell! 'root', 'usermod -a -G vboxsf user'
  end
end

job 'setup-shared-folders' do
  offline { vm.setup_shared_folders }
  online do
    config.shared_folders.each do |name, path|
      shell! 'user', "ln -s /media/sf_#{name}/ #{name}"
    end
    shell! 'user', 'rm .bash_profile'
    shell! 'user', 'ln -s /home/user/support/.bash_profile .bash_profile'
  end
end

job 'setup-development' do
  online do
    shell! 'root', 'rm /etc/katello/katello.yml'
    shell! 'root', "ln -s #{config.katello_path}/src/config/katello.yml /etc/katello/katello.yml"

    # reset oauth
    shell! 'user', "sudo #{config.katello_path}/src/script/reset-oauth shhhh"
    shell('root', 'service tomcat6 restart').success or shell!('root', 'service tomcat6 start')
    shell! 'root', 'service httpd restart'

    # create katello db
    wait_for(60) { shell('root', 'netstat -ln | grep -q ":5432\s"').success } ||
        raise('db is not running even after 60s')
    shell! 'root', "su - postgres -c 'createuser -dls katello  --no-password'"
    # only if /var/lib/pgsql/data was created from scratch in fedora17
    #   shell! 'root', "su - postgres -c 'createuser -dls candlepin  --no-password'"
    #   shell! ... katelo reset dbs
  end
end

job 'install-packaging' do
  online do
    yum_install *%w(tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt libxslt-devel scl-utils scl-utils-build spec2scl)

    # koji setup
    shell! 'user', 'mkdir $HOME/.koji'
    shell! 'user', 'ln -s $HOME/support/koji/katello-config $HOME/.koji/katello-config'
    shell! 'user', %(echo 'KOJI_OPTIONS=-c ~/.koji/katello-config build --nowait' | tee $HOME/.titorc)
    # patch koji-cli to be able to download scratch built rpms, see https://fedorahosted.org/koji/ticket/237
    shell! 'user', 'cat support/0001-koji-cli-add-download-scratch-build-command.patch | sudo patch -p0 /usr/bin/koji'
  end
end

job 'package_prepare' do
  online do
    shell! 'user', "git clone #{options[:source]} katello-build-source"
    shell! 'user', "cd katello-build-source; git checkout -b ci-#{options[:branch]} --track origin/#{options[:branch]}"

    yum_install "puppet" # workaround for missing puppet user when puppet is installed by yum-builddep
  end
end

job 'package_build_rpms' do
  online do
    extra_rpms = options[:extra_packages]
    yum_install(*extra_rpms) unless extra_rpms.empty?

    store_dir = "/home/user/support/builds/#{Time.now.strftime '%y.%m.%d-%H.%M.%S'}-#{vm.safe_name}/"
    shell! 'user', "mkdir -p #{store_dir}"

    spec_dirs = %w(src cli katello-configure katello-utils repos selinux/katello-selinux scripts/system-test)
    dist      = vm.fedora? ? '.fc16' : '.el6'
    logger.info "building src.rpms"
    src_rpms = spec_dirs.inject({}) do |hash, dir|
      result = shell! 'user', "cd katello-build-source/#{dir}; tito build --test --srpm --dist=#{dist}"
      result.out =~ /^Wrote: (.*src\.rpm)$/
      srpm_file = $1
      shell! 'user', "cp #{srpm_file} #{store_dir}"
      hash.update dir => srpm_file
    end

    rpms = if options[:use_koji]
             logger.info "building rpms in Koji"
             task_ids = spec_dirs.inject({}) do |hash, dir|
               tag    = vm.fedora? ? 'katello-nightly-fedora16' : 'katello-nightly-rhel6'
               result = shell! 'user',
                               "koji -c ~/.koji/katello-config build --scratch #{tag} #{src_rpms[dir]}"
               hash.update dir => /^Created task: (\d+)$/.match(result.out)[1]
             end

             logger.info "waiting until rpms are finished"
             shell! 'user', "koji -c ~/.koji/katello-config watch-task #{task_ids.values.join ' '}"

             logger.info "collecting the rpms"
             task_ids.map do |dir, task_id|
               result = shell! 'user',
                               "cd #{store_dir}; koji -c ~/.koji/katello-config download-scratch-build #{task_id}"
               result.out.split("\n").map { |line| store_dir + /^Downloading \[\d+\/\d+\]: (.+)$/.match(line)[1] }
             end
           else
             logger.info "building rpms locally"
             spec_dirs.map do |dir|
               shell! 'root', "yum-builddep -y #{src_rpms[dir]}"
               result = shell! 'user', "cd katello-build-source/#{dir}; tito build --test --rpm --dist=#{dist}"
               result.out =~ /Successfully built: (.*)\Z/
               $1.split(/\s/).tap do |rpms|
                 shell! 'user', "cp #{rpms.join(' ')} #{store_dir}"
                 logger.info "rpms: #{rpms.join(' ')}"
               end
             end
           end.flatten

    logger.info "All packaged rpms:\n  #{rpms.join("\n  ")}"

    to_install = rpms.select { |rpm| rpm !~ /headpin|devel|src\.rpm/ }
    install_args = ['root', "yum localinstall -y --nogpgcheck #{to_install.join ' '}"]
    if options[:force_install]
      result = shell *install_args
      unless result.success
        shell! 'root', "rpm -Uvh --oldpackage --force #{to_install.join ' '}"
      end
    else
      shell! *install_args
    end
  end
end

job 'reconfigure-katello', 'configure-katello'

job 'system-test' do
  online do
    wait_for(600, 20) { shell('user', 'katello -u admin -p admin ping').success } ||
        raise('Katello is not healthy')
    result = shell 'user', "/usr/share/katello/script/cli-tests/cli-system-test all #{options[:extra]}"
    logger.error "system tests FAILED" unless result.success
  end
end

job 'update' do
  online { shell! 'root', 'yum update -y' }
end

job 'relax-security' do
  online do
    # TODO only if /var/lib/pgsql/data - causes candlepin db problems (must create again and reset it
    # create new empty db structure - fedora 17 does not created during pg installation
    #   shell('root', 'rm -rf /var/lib/pgsql/data')
    #   shell('root', 'su - postgres -c "initdb -D /var/lib/pgsql/data"')

    # allow incoming connections to postgresql
    unless shell('root', 'cat /var/lib/pgsql/data/pg_hba.conf | grep "192.168.25.0/24"').success
      shell! 'root',
             'echo "host all all 192.168.25.0/24 trust" | tee -a /var/lib/pgsql/data/pg_hba.conf'
    end
    shell! 'root',
           "sed -i 's/^#.*listen_addresses =.*/listen_addresses = '\\'*\\'/ " +
               '/var/lib/pgsql/data/postgresql.conf'

    # allow incoming connections to elasticsearch
    el_config = '/etc/elasticsearch/elasticsearch.yml'
    shell! 'root', "sed -i 's/^.*network.bind_host.*/network.bind_host: 0.0.0.0/' #{el_config}"
    shell! 'root', "sed -i 's/^.*network.publish_host.*/network.publish_host: 0.0.0.0/' #{el_config}"
    shell! 'root', "sed -i 's/^.*network.host.*/network.host: 0.0.0.0/' #{el_config}"

    # reset katello secret to "katello"
    shell! 'root', "sed -i 's/^.*oauth_secret: .*/oauth_secret: shhhh/' /etc/pulp/server.conf"
    shell! 'root', "sed -i 's/^.*candlepin.auth.oauth.consumer.katello.secret =.*/" +
        "candlepin.auth.oauth.consumer.katello.secret = shhhh/' /etc/candlepin/candlepin.conf"
    shell! 'root', "sed -i 's/^.*oauth_secret: .*/    oauth_secret: shhhh/' /etc/katello/katello.yml"

    shell 'root', 'service httpd restart'
    shell 'root', 'service tomcat6 restart'
    shell 'root', 'service elasticsearch restart'
    shell 'root', 'service postgresql restart'
  end
end
