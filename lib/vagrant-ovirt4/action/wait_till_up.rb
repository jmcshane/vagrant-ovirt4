require 'log4r'
require 'vagrant-ovirt4/util/timer'
require 'vagrant/util/retryable'

module VagrantPlugins
  module OVirtProvider
    module Action

      # Wait till VM is started, till it obtains an IP address and is
      # accessible via ssh.
      class WaitTillUp
        include Vagrant::Util::Retryable

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_ovirt4::action::wait_till_up")
          @app = app
        end

        def call(env)
          # Initialize metrics if they haven't been
          env[:metrics] ||= {}

          # Get config.
          config = env[:machine].provider_config

          # Wait for VM to obtain an ip address.
          env[:ip_address] = nil
          env[:metrics]["instance_ip_time"] = Util::Timer.time do
            env[:ui].info(I18n.t("vagrant_ovirt4.waiting_for_ip"))
            for i in 1..300
              # If we're interrupted don't worry about waiting
              next if env[:interrupted]

              # Get VM.
              server = env[:vms_service].list({:search => "id=#{env[:machine].id}"})[0]
              if server == nil
                raise NoVMError, :vm_name => ''
              end

              nics_service = env[:vms_service].vm_service(env[:machine].id).nics_service
              nics = nics_service.list
              env[:ip_address] = nics.collect { |nic_attachment| env[:connection].follow_link(nic_attachment).reported_devices.collect { |dev| dev.ips.collect { |ip| ip.address if ip.version == 'v4' } } }.flatten.reject { |ip| ip.nil? }.first rescue nil
              @logger.debug("Got output #{env[:ip_address]}")
              break if env[:ip_address] =~ /[0-9\.]+/
              sleep 2
            end
          end
          terminate(env) if env[:interrupted]
          @logger.info("Got IP address #{env[:ip_address]}")
          @logger.info("Time for getting IP: #{env[:metrics]["instance_ip_time"]}")
          
         terminate(env) if env[:interrupted]
          @logger.info("Time for SSH ready: #{env[:metrics]["instance_ssh_time"]}")

          # Booted and ready for use.
          env[:ui].info(I18n.t("vagrant_ovirt4.ready"))
          
          @app.call(env)
        end

        def recover(env)
          return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)

          if env[:machine].provider.state.id != :not_created
            # Undo the import
            terminate(env)
          end
        end

        def terminate(env)
          destroy_env = env.dup
          destroy_env.delete(:interrupted)
          destroy_env[:config_validate] = false
          destroy_env[:force_confirm_destroy] = true
          env[:action_runner].run(Action.action_destroy, destroy_env)        
        end
      end
    end
  end
end
