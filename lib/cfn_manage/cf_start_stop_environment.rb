require 'aws-sdk-s3'
require 'aws-sdk-ec2'
require 'aws-sdk-cloudformation'
require 'aws-sdk-rds'
require 'aws-sdk-cloudwatch'
require 'aws-sdk-autoscaling'
require 'aws-sdk-ecs'
require 'aws-sdk-docdb'

require 'cfn_manage/cf_common'
require 'cfn_manage/aws_credentials'
require 'cfn_manage/file_manager'
require 'json'
require 'yaml'
require 'cfn_manage/start_stop_handler_factory'
require 'cfn_manage/s3_handler'
require 'cfn_manage/resource'
require 'cfn_manage/resource_controller'

module CfnManage
  module CloudFormation
    class EnvironmentRunStop

      @cf_client = nil
      @root_stack_name = nil

      # TODO: put in a config file
      @@resource_start_priorities = {
          'AWS::RDS::DBInstance' => '100',
          'AWS::RDS::DBCluster' => '100',
          'AWS::DocDB::DBCluster' => '100',
          'AWS::AutoScaling::AutoScalingGroup' => '200',
          'AWS::EC2::Instance' => '200',
          'AWS::EC2::SpotFleet' => '200',
          'AWS::Transfer::Server' => '200',
          'AWS::ECS::Cluster' => '250',
          'AWS::CloudWatch::Alarm' => '300'
      }

      def initialize(run_configuration)
        # TODO: remove all ENV statements and source them through the 'run_configuration' or some other means
        @all_stack_resources = {}
        @environment_resources = {}
        @run_configuration = run_configuration
        credentials = CfnManage::AWSCredentials.get_session_credentials('start_stop_environment')
        @cf_client = Aws::CloudFormation::Client.new(credentials: credentials, retry_limit: 20)
        @resource_handlers = CfnManage::StartStopHandlerFactory.get_resource_handlers(credentials)
        @resource_controller = ResourceController.new(resource_handlers: @resource_handlers, run_configuration: @run_configuration, s3_bucket: ENV['BUCKET'], credentials: credentials)
        @file_manager = CfnManage::FileManager.new(run_configuration)

        if run_configuration[:dry_run]
          $log.warn("** Dry run is set! The following actions will NOT have any effect. **")
        end

      rescue NoMethodError => e
        puts "Got No Method Error on CloudFormation::initialize, this often means that you're missing a AWS_DEFAULT_REGION"
        $log.error("#{e.to_s}")
        $log.error(e.backtrace.join("\n\t"))
        raise e
      rescue Aws::Sigv4::Errors::MissingCredentialsError => e
        puts "Got Missing Credentials Error on CloudFormation::initialize, this often means that AWS_PROFILE is unset, or no default credentials were provided."
      end


      def start_environment(stack_name)
        @root_stack_name = stack_name
        $log.info("Starting environment: #{stack_name}")
        collect_resources(stack_name)
        #Common.visit_stack(@cf_client, stack_name, method(:collect_resources), true)
        do_start_assets
        configuration = { stack_running: true }
        #save_item_configuration("environment_data/stack-#{stack_name}", configuration) unless @dry_run
        $log.info("Environment #{stack_name} started")
      end


      def stop_environment(stack_name)
        @root_stack_name = stack_name
        $log.info("Stopping environment #{stack_name}")
        #Common.visit_stack(@cf_client, stack_name, method(:collect_resources), true)
        collect_resources(stack_name)
        do_stop_assets
        configuration = { stack_running: false }
        #save_item_configuration("environment_data/stack-#{stack_name}", configuration) unless @dry_run
        $log.info("Environment #{stack_name} stopped")
      end

      def start_resource(resource_id,resource_type)
        @environment_resources << Resource.new(
          id: resource_id,
          priority: @@resource_start_priorities[resource_type],
          type: resource_type
        )

        do_start_assets
      end

      def stop_resource(resource_id,resource_type)
        @environment_resources << Resource.new(
          id: resource_id,
          priority: @@resource_start_priorities[resource_type],
          type: resource_type
        )
        do_stop_assets
      end

      def prepare_resource_execution_order(reverse=false)
        # 1. Add any dependencies from the config to the resources
        # 2. Group resources according to their priority
        dependency_list = @file_manager.dependency_list

        # @environment_resources = dev-$stack_$resource

        # - Iterate over the dependencies to find a resource X with a 'depends_on'
        # - For each of X's dependencies [Y], try to find  see if the resource Y exists in the resource list
        # -   If it does, add Y to X's dependencies
        # - Else, search for it in the resource list. Once found, add it to resource X

        # We need to search the resource list because the provided logical ID is only a partial string


        dependency_list.each do |name, config|
          next if !config.key?('depends_on')

          logical_stack_id = config['stack']
          logical_resource_id = config['resource']
          resource_identifier = "#{logical_stack_id}.#{logical_resource_id}"

          $log.debug("Searching for resource #{resource_identifier} ...")
          resource = @environment_resources[resource_identifier]

          if resource.nil?
            fatal_exit("Dependency '#{resource_identifier}' does not exist in stack '#{@root_stack_name}' or does not have a resource handler.")
          end

          # Run the same code as above for each of the resource's dependencies.
          config['depends_on'].each do |dependency|
            dependency_logical_stack_id = dependency_list[dependency]['stack']
            dependency_logical_resource_id = dependency_list[dependency]['resource']
            dependency_resource_identifier = "#{dependency_logical_stack_id}.#{dependency_logical_resource_id}"

            $log.debug("Searching for dependency resource #{dependency_resource_identifier} ...")
            dependency_resource = @environment_resources[dependency_resource_identifier]

            if dependency_resource.nil?
              fatal_exit("Dependency '#{dependency_resource_identifier}' does not exist in stack '#{@root_stack_name}' or does not have a resource handler.")
            end

            resource.dependencies << dependency_resource
            $log.debug("Added '#{dependency_resource_identifier}' as a dependency to resource '#{resource_identifier}'")
          end
        end if !dependency_list.empty?

        resources = {}

        # Group resources by their priority
        @environment_resources.values.each do |res|
          resources[res.priority] = [] if !resources.key?(res.priority)
          resources[res.priority] << res
        end

        return resources.sort()
        # resources = @environment_resources.values.sort_by { |k| k.priority }
        # resources.reverse! if reverse
        # return resources.partition { |k| k.priority }
      end

      def do_stop_assets
        # sort start resource by priority
        resources = prepare_resource_execution_order(true)

        resources.each do |priority|
          priority.each do |resource|
            begin
              $log.info("Stopping resource #{resource.id}")
              @resource_controller.stop(resource)
            rescue => e
              $log.error("An exception occurred during stop operation against resource #{resource.id}")
              $log.error("#{e.to_s}")
              $log.error(e.backtrace.join("\n\t"))
              if not @continue_on_error
                raise e
              end
            end
          end

          if @run_configuration[:dry_run] or @run_configuration[:skip_wait]
            break
          end

          priority.each do |resource|
            begin
              resource[:handler].wait('stopped')
            rescue => e
              $log.error("An exception occurred during wait operation against resource #{resource.id}")
              $log.error("#{e.to_s}")
              $log.error(e.backtrace.join("\n\t"))
              if not @continue_on_error
                raise e
              end
            end
          end
        end
      end

      def do_start_assets
        # sort start resource by priority

        # This needs to be a case statement, which takes an action depending on the group's state:
        #
        resources = prepare_resource_execution_order()

        resources.each_with_index do |(priority,batch),index|
          $log.debug("Starting batch #{index+1}/#{resources.size()} containing #{batch.size()} resources of priority #{priority} ...")
          resource_count = batch.size()

          current_group_state = ExecutionStates::Starting
          $log.debug("Begin state: Starting")

          loop do
            ready_count = 0

            case current_group_state
              when ExecutionStates::Starting
                batch.each do |resource|
                  begin
                    # We must continuously attempt to start the resources since there must be some with dependencies.
                    $log.info("Starting resource: #{resource.id}")
                    @resource_controller.start(resource)

                    if resource.execution_state >= ExecutionStates::Starting
                      ready_count += 1
                    end
                  rescue => e
                    # TODO: should this be put in the ResourceController class?
                    $log.error("An exception occurred during start operation against resource #{resource.id}")
                    $log.error("#{e.to_s}")
                    $log.error(e.backtrace.join("\n\t"))
                    if not @continue_on_error
                      raise e
                    end
                  end
                end

                # Check if we can move to the next state
                if ready_count == resource_count
                  $log.debug("Completed state: Starting")
                  $log.debug("Begin state: HealthChecking")
                  current_group_state = ExecutionStates::HealthChecking
                end

              when ExecutionStates::HealthChecking
                if @run_configuration[:dry_run] or @run_configuration[:skip_wait]
                  $log.debug("Completed state: HealthChecking")
                  $log.debug("Begin state: Running")
                  current_group_state = ExecutionStates::Running
                  next
                end

                # Check that each resource is healthy/available
                batch.each do |resource|
                  begin
                    if @resource_controller.is_available(resource)
                      ready_count += 1
                    end
                  rescue => e
                    $log.error("An exception occurred when checking the status of resource #{resource.id}")
                    $log.error("#{e.to_s}")
                    $log.error(e.backtrace.join("\n\t"))
                    if not @continue_on_error
                      raise e
                    end
                  end
                end

                # Check if we can move to the next state
                if ready_count == resource_count
                  $log.debug("Completed state: HealthChecking")
                  $log.debug("Begin state: Running")
                  current_group_state = ExecutionStates::Running
                else
                  sleep(10)
                end

              when ExecutionStates::Running
                $log.debug("Running the post-start handler for each resource.")

                batch.each do |resource|
                  begin
                    @resource_controller.post_start(resource)
                  rescue => e
                    $log.error("An exception occurred when checking the status of resource #{resource.id}")
                    $log.error("#{e.to_s}")
                    $log.error(e.backtrace.join("\n\t"))
                    if not @continue_on_error
                      raise e
                    end
                  end
                end
                # The environment is in the desired state.
                $log.debug("Completed state: Running")
                break
              else
                $log.debug("Completed state: Running")
                break
            end
          end
        end
      end

      def collect_resources(stack_name)
        case @run_configuration[:collect_method]
          when 'Query'
            visit_stack(stack_name)
          when 'File'
            @file_manager.load_resources_from_file(method(:get_resources))
        end

        $log.debug("Collected a total of #{@environment_resources.size()} resources to operate on.")

        if !@run_configuration[:save_to_filename].nil?
          @file_manager.save_resources_to_file(@all_stack_resources)
        end
      end

      def get_resources(resources:, function_handler: nil)
        # resources: a data structure containing a set of CloudFormation resources
        #            in the format returned by querying `describe_stack_resources`
        # function_handler: the function to be called to handle resources of type 'AWS::CloudFormation::Stack'

        resources['stack_resources'].each do |resource|
          physical_id = resource['physical_resource_id']
          logical_id = resource['logical_resource_id']
          type = resource['resource_type']
          logical_stack_name = resource['stack_name'].split('-')[1]

          if function_handler
            if resource['resource_type'] == 'AWS::CloudFormation::Stack'
              # call recursively
              substack_name = resource['physical_resource_id'].split('/')[1]
              function_handler(substack_name)
            end
          end

          if @resource_handlers.keys().include?(type)
            # Only create resources if they have a handler.
            # Index them by their logical resource ID (and its stack name
            # to prevent name conflicts) in case a dependency file was provided.
            @environment_resources["#{logical_stack_name}.#{logical_id}"] = Resource.new(
              id: physical_id,
              priority: @@resource_start_priorities[type],
              type: type
            )
            $log.debug("Collected resource: type=#{type} logical_id=#{logical_id} physical_id=#{physical_id}")
          end
        end
      end

      def visit_stack(stack_name)
        $log.debug("")
        $log.debug("Collecting resources from stack: #{stack_name} ...")
        resources = @cf_client.describe_stack_resources(stack_name: stack_name)
        $log.debug("Collected #{resources['stack_resources'].size()} resources.")

        @all_stack_resources[stack_name] = resources.to_h  # Used for saving to disk

        get_resources(resources: resources, function_handler: visit_stack)
      end

      private :do_stop_assets, :do_start_assets, :collect_resources

    end
  end
end

module ExecutionStates
  None = 0
  Starting = 1
  HealthChecking = 2
  Running = 3
  Stopping = 4
  Stopped = 5
end
