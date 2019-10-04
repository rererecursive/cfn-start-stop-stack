require 'cfn_manage/aws_credentials'
require 'cfn_manage/abstract_start_stop_handler'

module CfnManage

  class AlarmStartStopHandler < AbstractStartStopHandler

    def initialize(credentials)
      params = {retry_limit: 20, credentials: credentials}
      @cw_client = Aws::CloudWatch::Client.new(params)
      @cw_resource = Aws::CloudWatch::Resource.new(client: @cw_client)
    end

    def start(resource, run_configuration)
      alarm = @cw_resource.alarm(resource.id)

      if alarm.actions_enabled
        $log.info("Alarm #{alarm.alarm_arn} actions already enabled")
        return
      end

      $log.info("Enabling alarm #{alarm.alarm_arn}")
      return true if run_configuration[:dry_run]

      alarm.enable_actions({})
      return true
    end

    def stop
      alarm = @cw_resource.alarm(resource.id)

      if not alarm.actions_enabled
        $log.info("Alarm #{alarm.alarm_arn} actions already disabled")
        return true
      end

      $log.info("Disabling actions on alarm #{alarm.alarm_arn}")
      return true if run_configuration[:dry_run]
      alarm.disable_actions({})
      return true
    end

  end

end
