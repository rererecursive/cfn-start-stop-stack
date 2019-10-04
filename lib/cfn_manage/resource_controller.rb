class ResourceController
  def initialize(resource_handlers:, run_configuration:, s3_bucket:, credentials:)
    @s3_handler = S3Handler.new(bucket: s3_bucket, credentials: credentials)
    @resource_handlers = resource_handlers
    @run_configuration = run_configuration
  end

  def start(resource)
    # Attempt to start a resource and its dependencies.
    if resource.available
      return true
    end

    if !resource.configuration
      resource.configuration = @s3_handler.get_object_configuration(resource)
    end

    dependencies = resource.dependencies
    if !dependencies.empty?
      # Recursively call the dependencies until one has started.
      # We don't want to start the entire dependency chain at once since we
      # need to wait for each resource to become healthy before starting the next.
      dependencies.each do |res|
        if !start(res)
          return false
        end
      end
    end

    handler = @resource_handlers[resource.type]
    handler.start(resource, @run_configuration)
    resource.execution_state = ExecutionStates::HealthChecking
    resource.available = false

    return false
  end

  def stop(resource)
    # Attempt to stop a resource and its dependencies.
    if !resource.available
      return true
    end

    if !resource.configuration
      resource.configuration = @s3_handler.get_object_configuration(resource)
    end

    dependencies = resource.dependencies
    if !dependencies.empty?
      dependencies.each do |res|
        if !stop(res)
          return false
        end
      end
    end

    handler = @resource_handlers[resource.type]
    handler.stop(resource, @run_configuration)
    resource.execution_state = ExecutionStates::Running

    return false
  end

  def post_start(resource)
    if resource.execution_state == ExecutionStates::HealthChecking
      handler = @resource_handlers[resource.type]
      handler.post_start(resource, @run_configuration)
      resource.execution_state = ExecutionStates::Running
    end
  end

  def is_available(resource)
    if !resource.available
      handler = @resource_handlers[resource.type]
      handler.check_health(resource, @run_configuration)
    end

    return resource.available
  end
end