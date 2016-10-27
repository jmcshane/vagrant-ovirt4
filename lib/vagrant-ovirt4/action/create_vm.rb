require 'log4r'
require 'vagrant/util/retryable'

module VagrantPlugins
  module OVirtProvider
    module Action
      class CreateVM
        include Vagrant::Util::Retryable

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant_ovirt4::action::create_vm")
          @app = app
        end

        def call(env)
          # Get config.
          config = env[:machine].provider_config

          # Gather some info about domain
          #name = env[:domain_name]
          name = SecureRandom.hex(4)

          # Output the settings we're going to use to the user
          env[:ui].info(I18n.t("vagrant_ovirt4.creating_vm"))
          env[:ui].info(" -- Name:          #{name}")
          env[:ui].info(" -- Cluster:       #{config.cluster}")

          # Create oVirt VM.
          attr = {
              :name     => name,
              :cluster  => {
                :name => config.cluster,
              },
              :template  => {
                :name => config.template,
              },
          }

          server = env[:vms_service].add(attr)

          # Immediately save the ID since it is created at this point.
          env[:machine].id = server.id

          # Wait till all volumes are ready.
          env[:ui].info(I18n.t("vagrant_ovirt4.wait_for_ready_vm"))
          for i in 0..10
            ready = true
            env[:vms_service].list({:search => "id=#{env[:machine].id}"})[0]
            vm_service = env[:vms_service].vm_service(env[:machine].id)
            disk_attachments_service = vm_service.disk_attachments_service
            disk_attachments = disk_attachments_service.list
            disk_attachments.each do |disk_attachment|
              disk = env[:connection].follow_link(disk_attachment.disk)
              if disk.status != 'ok'
                ready = false
                break
              end
            end
            break if ready
            sleep 2
          end

          if not ready
            raise Errors::WaitForReadyVmTimeout
          end

          @app.call(env)
        end

        def recover(env)
          return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)

          # Undo the import
          env[:ui].info(I18n.t("vagrant_ovirt4.error_recovering"))
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