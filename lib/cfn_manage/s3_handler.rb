class S3Handler
  def initialize(bucket:, credentials:)
    @bucket = bucket
    @prefix = 'environment_data/resource'
    @filename = 'config.json'
    @s3_client = Aws::S3::Client.new(credentials: credentials, retry_limit: 20)
  end

  def get_object_configuration(resource)
      configuration = nil
      begin
        key = [@prefix, resource.id, 'latest', @filename].join('/')
        $log.info("Reading object configuration from s3://#{@bucket}/#{key}")

        # fetch and deserialize and s3 object
        configuration = JSON.parse(@s3_client.get_object(bucket: @bucket, key: key).body.read)

        $log.info("Configuration:#{configuration}")
      rescue Aws::S3::Errors::NoSuchKey
        $log.warn("Could not find configuration at s3://#{@bucket}/#{key}")
      end
      configuration
    end

    def save_item_configuration(resource)
      # save latest configuration, and one time-based versioned
      key = [@prefix, resource.id].join('/')
      s3_keys = [
          "#{key}/latest/#{@filename}",
          "#{key}/#{Time.now.getutc.to_i}/#{@filename}"
      ]
      s3_keys.each do |key|
        $log.info("Saving configuration to #{@bucket}/#{key}\n#{resource.configuration}")
        $log.info(resource.configuration.to_yaml)
        @s3_client.put_object({
            bucket: @bucket,
            key: key,
            body: JSON.pretty_generate(resource.configuration)
        })
      end
    end

  # This class takes a Resource as its argument and returns or saves its state to S3
end
