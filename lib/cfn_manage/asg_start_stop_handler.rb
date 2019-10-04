require 'cfn_manage/aws_credentials'
require 'cfn_manage/abstract_start_stop_handler'

module CfnManage

  class AsgStartStopHandler < AbstractStartStopHandler

    def initialize(credentials)
      params = {retry_limit: 20, credentials: credentials}
      @asg_client = Aws::AutoScaling::Client.new(params)
      # TODO: remove below; use the EC2 handler
      @ec2_client = Aws::EC2::Client.new(params)
      #@ec2_handler = CfnManage::Ec2StartStopHandler.new()
    end

    # def initialize(asg_id, skip_wait)
    #   @asg_name = asg_id
    #   @skip_wait = skip_wait
    #   @asg_suspend_termination = (ENV.key?('ASG_SUSPEND_TERMINATION') and ENV['ASG_SUSPEND_TERMINATION'] == '1')
    #   credentials = CfnManage::AWSCredentials.get_session_credentials("stopasg_#{@asg_name}")
    #   @asg_client = Aws::AutoScaling::Client.new(retry_limit: 20)
    #   @ec2_client = Aws::EC2::Client.new(retry_limit: 20)
    #   if credentials != nil
    #     @asg_client = Aws::AutoScaling::Client.new(credentials: credentials, retry_limit: 20)
    #     @ec2_client = Aws::EC2::Client.new(credentials: credentials, retry_limit: 20)
    #   end

    #   asg_details = @asg_client.describe_auto_scaling_groups(
    #       auto_scaling_group_names: [@asg_name]
    #   )
    #   if asg_details.auto_scaling_groups.size() == 0
    #     raise "Couldn't find ASG #{@asg_name}"
    #   end
    #   @asg = asg_details.auto_scaling_groups[0]
    # end

    def stop
      # check if already stopped
      if @asg.min_size == @asg.max_size and @asg.max_size == @asg.desired_capacity and @asg.min_size == 0
        $log.info("ASG #{@asg_name} already stopped")
        # nil and false configurations are not saved
        return nil
      else

        puts @asg.auto_scaling_group_name

        unless @asg_suspend_termination
          # store asg configuration to S3
          configuration = {
              desired_capacity: @asg.desired_capacity,
              min_size: @asg.min_size,
              max_size: @asg.max_size
          }

          $log.info("Setting desired capacity to 0/0/0 for ASG #{@asg.auto_scaling_group_name}")

          puts @asg.auto_scaling_group_name
          @asg_client.update_auto_scaling_group({
              auto_scaling_group_name: "#{@asg.auto_scaling_group_name}",
              min_size: 0,
              max_size: 0,
              desired_capacity: 0
          })
          return configuration
        else

          configuration = {
            desired_capacity: @asg.desired_capacity,
            min_size: @asg.min_size,
            max_size: @asg.max_size,
            suspended_processes: @asg.suspended_processes
          }

          $log.info("Suspending processes for ASG #{@asg.auto_scaling_group_name}A")

          @asg_client.suspend_processes({
            auto_scaling_group_name: "#{@asg.auto_scaling_group_name}",
          })

          $log.info("Stopping all instances in ASG #{@asg.auto_scaling_group_name}A")

          @asg.instances.each do |instance|
            @instance_id = instance.instance_id
            @instance = Aws::EC2::Resource.new(client: @ec2_client, retry_limit: 20).instance(@instance_id)

            if %w(stopped stopping).include?(@instance.state.name)
              $log.info("Instance #{@instance_id} already stopping or stopped")
              return
            end

            $log.info("Stopping instance #{@instance_id}")
            @instance.stop()
          end

          return configuration

        end

      end

    end

    def stop(resource)
      # TODO
    end

    def start(resource, run_configuration)
      configuration = resource.configuration
      if configuration.empty?
        $log.warn("No configuration found for #{resource.id}, skipping..")
        return
      end

      if !run_configuration[:asg_suspend_termination]
        # restore asg sizes
        $log.info("Starting ASG #{resource.id} with following configuration:\n#{configuration}")

        if !run_configuration[:dry_run]
          @asg_client.update_auto_scaling_group({
            auto_scaling_group_name: resource.id,
            min_size: configuration['min_size'],
            max_size: configuration['max_size'],
            desired_capacity: configuration['desired_capacity']
          })
        end
      else
        $log.info("Starting instances for ASG #{resource.id}...")

        # TODO: use the EC2 handler for this
        @asg.instances.each do |instance|
          instance_id = instance.instance_id

          if !run_configuration[:dry_run]
            instance = Aws::EC2::Resource.new(client: @ec2_client, retry_limit: 20).instance(instance_id)

            if %w(running).include?(instance.state.name)
              $log.info("Instance #{instance_id} already running")
            end
            instance.start()
          end

          $log.info("Started instance #{instance_id}")
        end
      end
    end

    def check_health(resource)
      $log.info("Checking health status for instances for ASG #{resource.id}")

      asg_curr_details = @asg_client.describe_auto_scaling_groups(
        auto_scaling_group_names: [resource.id]
      )
      asg_status = asg_curr_details.auto_scaling_groups[0]

      asg_status.instances.each do |instance|
        instance_health = instance.health_status
        $log.info("Instance: #{instance.instance_id}, Status: #{instance_health}")

        if instance_health != "Healthy"
          resource.available = false
        end
      end

      return resource.available
    end

    def post_start(resource, run_configuration)
      $log.info("Resuming all processes for ASG #{resource.id}")

      return true if run_configuration[:dry_run]

      @asg_client.resume_processes({
        auto_scaling_group_name: "#{resource.id}",
      })

      if configuration.key?(:suspended_processes)
        $log.info("Suspending processes stored in configuration for ASG #{resource.id}")

        @asg_client.suspend_processes({
          auto_scaling_group_name: "#{resource.id}",
          scaling_processes: configuration['suspended_processes'],
        })
      end
    end


    # Old
    # def start(configuration)
    #   if configuration.nil?
    #     $log.warn("No configuration found for #{@asg_name}, skipping..")
    #     return
    #   end
    #   $log.info("Starting ASG #{@asg_name} with following configuration\n#{configuration}")

    #   unless @asg_suspend_termination
    #     # restore asg sizes
    #     @asg_client.update_auto_scaling_group({
    #       auto_scaling_group_name: @asg_name,
    #       min_size: configuration['min_size'],
    #       max_size: configuration['max_size'],
    #       desired_capacity: configuration['desired_capacity']
    #     })
    #   else

    #     $log.info("Starting instances for ASG #{@asg_name}...")

    #     @asg.instances.each do |instance|
    #       @instance_id = instance.instance_id
    #       @instance = Aws::EC2::Resource.new(client: @ec2_client, retry_limit: 20).instance(@instance_id)

    #       if %w(running).include?(@instance.state.name)
    #         $log.info("Instance #{@instance_id} already running")
    #         return
    #       end
    #       $log.info("Starting instance #{@instance_id}")
    #       @instance.start()
    #     end

    #     unhealthy = true

    #     $log.info("Checking health status for instances for ASG #{@asg_name}")

    #     while unhealthy do

    #       asg_curr_details = @asg_client.describe_auto_scaling_groups(
    #         auto_scaling_group_names: [@asg_name]
    #       )
    #       @asg_status = asg_curr_details.auto_scaling_groups[0]

    #       allHealthy = 0

    #       @asg_status.instances.each do |instance|
    #         @instance_health = instance.health_status
    #         if @instance_health == "Healthy"
    #           allHealthy += 1
    #         else
    #           $log.info("Instance #{instance.instance_id} not currently healthy...")
    #           sleep(15)
    #         end
    #       end

    #       if allHealthy == @asg_status.instances.length
    #         $log.info("All instances healthy in ASG #{@asg_name}")
    #         unhealthy = false
    #         break
    #       end

    #     end

    #     $log.info("Resuming all processes for ASG #{@asg_name}")

    #     @asg_client.resume_processes({
    #       auto_scaling_group_name: "#{@asg.auto_scaling_group_name}",
    #     })

    #     if configuration.key?(:suspended_processes)

    #       $log.info("Suspending processes stored in configuration for ASG #{@asg_name}")

    #       @asg_client.suspend_processes({
    #         auto_scaling_group_name: "#{@asg.auto_scaling_group_name}",
    #         scaling_processes: configuration['suspended_processes'],
    #       })
    #     end

    #   end

    # end
  end
end
