require 'cfn_manage/aws_credentials'
require 'cfn_manage/abstract_start_stop_handler'

module CfnManage

  class Ec2StartStopHandler < AbstractStartStopHandler

    # @started_states = %w(pending running)
    # @stopped_states = %w(shutting-down terminated stopping stopped)

    # def initialize(resource)
    #   @resource = resource
    #   @instance_id = resource.instance_id
    #   credentials = CfnManage::AWSCredentials.get_session_credentials("stoprun_#{@instance_id}")
    #   ec2_client = Aws::EC2::Client.new(credentials: credentials, retry_limit: 20)
    #   @instance = Aws::EC2::Resource.new(client: ec2_client, retry_limit: 20).instance(@instance_id)
    # end

    def initialize(credentials)
      client = Aws::EC2::Client.new(credentials: credentials, retry_limit: 20)
      @ec2_resource = Aws::EC2::Resource.new(client: client, retry_limit: 20)
    end

    def start(resource, run_configuration)
      instance = @ec2_resource.instance(resource.id)

      case
        when instance.state.name == 'running'
          resource.available = true
        when instance.state.name != 'pending'
          $log.info("Starting instance #{instance_id}")
          instance.start() if !run_configuration[:dry_run]
          return true
      end

      $log.info("Instance #{instance_id} is already #{instance.state.name}")  # running / pending
      return false
    end

    def stop
      return true if run_configuration[:dry_run]

      instance = @ec2_resource.instance(resource.id)

      if %w(stopped stopping shutting-down terminated).include?(instance.state.name)
        $log.info("Instance #{instance_id} already #{instance.state.name}")
        resource.available = false
        return false
      end

      $log.info("Stopping instance #{instance_id}")
      instance.stop()
      resource.available = false

      # empty configuration for ec2 instances
      return true
    end

    def check_health(resource)
      $log.info("Checking health status for instance: #{resource.id}")

      instance = @ec2_resource.instance(resource.id)

      case
        when instance.state.name == 'running'
          resource.available = true
        when instance.state.name != 'pending'
          resource.available = false
      end

      return resource.available
    end

    # def stop
    #   if %w(stopped stopping).include?(instance.state.name)
    #     $log.info("Instance #{instance_id} already stopping or stopped")
    #     return
    #   end
    #   $log.info("Stopping instance #{instance_id}")
    #   instance.stop()

    #   # empty configuration for ec2 instances
    #   return {}
    # end

  end
end
