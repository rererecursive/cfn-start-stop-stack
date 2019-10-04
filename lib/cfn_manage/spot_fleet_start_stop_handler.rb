require 'cfn_manage/aws_credentials'
require 'cfn_manage/abstract_start_stop_handler'

module CfnManage

  class SpotFleetStartStopHandler < AbstractStartStopHandler

    # def initialize(fleet_id, skip_wait)
    #   @fleet_id = fleet_id
    #   @skip_wait = skip_wait
    #   credentials = CfnManage::AWSCredentials.get_session_credentials("startstopfleet_#{fleet_id}")
    #   @ec2_client = Aws::EC2::Client.new(retry_limit: 20)
    #   if credentials != nil
    #     @ec2_client = Aws::EC2::Client.new(credentials: credentials, retry_limit: 20)
    #   end

    #   @fleet = @ec2_client.describe_spot_fleet_requests({spot_fleet_request_ids:[fleet_id]})
    #   @fleet = @fleet.spot_fleet_request_configs[0].spot_fleet_request_config
    # end

    def initialize(credentials)
      @ec2_client = Aws::EC2::Client.new(retry_limit: 20)
    end

    def start(resource, run_configuration)
      return true if run_configuration[:dry_run]

      fleet = @ec2_client.describe_spot_fleet_requests({spot_fleet_request_ids:[resource.id]})
      fleet = fleet.spot_fleet_request_configs[0].spot_fleet_request_config

      $log.info("Setting fleet #{resource.id} capacity to #{resource.configuration['target_capacity']}")
      @ec2_client.modify_spot_fleet_request({
          spot_fleet_request_id: resource.id,
          target_capacity: resource.configuration['target_capacity'],
      })

      return true
    end


    # def start(configuration)

    #   $log.info("Setting fleet #{@fleet_id} capacity to #{configuration['target_capacity']}")
    #   @ec2_client.modify_spot_fleet_request({
    #       spot_fleet_request_id: @fleet_id,
    #       target_capacity: configuration['target_capacity'],
    #   })

    #   return configuration
    # end

    def stop(resource, run_configuration)
      # TODO
    end

    def stop
      return true if run_configuration[:dry_run]

      if @fleet.target_capacity == 0
        $log.info("Spot fleet #{@fleet_id} already stopped")
        return nil
      end

      configuration = {
          target_capacity: @fleet.target_capacity
      }

      $log.info("Setting fleet #{@fleet_id} capacity to 0")
      @ec2_client.modify_spot_fleet_request({
          spot_fleet_request_id: @fleet_id,
          target_capacity: 0,
      })

      return configuration
    end

    def wait(wait_states=[])
      $log.debug("Not waiting for spot fleet #{@fleet_id}")
    end

  end

end
