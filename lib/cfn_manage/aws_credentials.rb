require 'aws-sdk-core'

module CfnManage

  class AWSCredentials

    def self.get_session_credentials(session_name)

      #check if AWS_ASSUME_ROLE exists
      session_name =  "#{session_name.gsub('_','-')}-#{Time.now.getutc.to_i}"
      if session_name.length > 64
        session_name = session_name[-64..-1]
      end
      assume_role = ENV['AWS_ASSUME_ROLE'] or nil
      if not assume_role.nil?
        $log.debug("Obtaining credentials from assuming role.")
        return Aws::AssumeRoleCredentials.new(
            role_arn: assume_role,
            role_session_name: session_name
        )
      end

      # check if explicitly set shared credentials profile
      if ENV.key?('CFN_AWS_PROFILE')
        $log.debug("Using AWS profile: #{ENV['CFN_AWS_PROFILE']}.")
        return Aws::SharedCredentials.new(profile_name: ENV['CFN_AWS_PROFILE'])
      end

      # check the environment variables
      if ENV.key?('AWS_SESSION_TOKEN')
        $log.debug("Using AWS credentials from environment variables.")
        return Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'], ENV['AWS_SESSION_TOKEN'])
      end

      # check if Instance Profile available
      $log.debug("Attempting to fetch credentials from instance profile...")
      # TODO: uncomment
      # credentials = Aws::InstanceProfileCredentials.new(retries: 2, http_open_timeout:1)
      # return credentials unless credentials.credentials.access_key_id.nil?

      # use default profile
      $log.debug("Using credentials from the default profile.")
      return Aws::SharedCredentials.new()

    end
  end
end
