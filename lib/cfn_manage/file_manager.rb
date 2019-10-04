module CfnManage
  class FileManager
    attr_accessor :dependency_list

    def initialize(run_configuration)
      @run_configuration = run_configuration
      @dependency_list = process_config_file(filename: run_configuration[:config_file])
    end

    def process_config_file(filename:)
      if filename.nil?
        return []
      end

      $log.debug("Reading config file: #{filename}")
      contents = YAML.load(File.read(filename))
      dependencies = contents['dependencies']

      prove_correctness(dependencies)
      #dependencies = logify(dependencies)
      return dependencies
    end

    def load_resources_from_file(func)
      filename = @run_configuration[:load_from_filename]
      $log.info("Loading stack resources from file: #{filename}")
      @all_stack_resources = JSON.parse(File.read(filename))
      $log.debug("Loaded #{@all_stack_resources.size()} stacks.")

      @all_stack_resources.each do |stack, resources|
        func.call(resources: resources)
      end
    end

    def save_resources_to_file(resources)
      filename = @run_configuration[:save_to_filename]

      File.open(filename, 'w') do |file|
        file.write(JSON.pretty_generate(resources.to_h))
      end

      $log.info("Stack resources were saved to file: #{filename}")
    end

    def logify(dependencies)
      # Maybe I should keep the structure in the YAML file so that the searching of
      # resources is much easier.

      # Map every resource's name to its logical ID
      logical_names = {}

      if dependencies
        dependencies.each do |name,config|
          # Ensure the config is correct
          if !(['stack', 'resource'] - config.keys()).empty?
            $log.fatal("The resource '#{name}' in file '#{filename}' must have values for keys 'stack' and 'resource'")
            exit(1)
          end

          logical_name = logical_identifier(config)
          logical_names[logical_name] = {}

          depends_on = config['depends_on']
          if depends_on
            # Ensure referenced resources exist
            depends_on.each do |res|
              if !dependencies.keys().include?(res)
                $log.fatal("The resource '#{res}' referenced by '#{name}' does not exist.")
                exit(1)
              end
              if !logical_names[logical_name].key?(:depends_on)
                logical_names[logical_name][:depends_on] = []
              end

              logical_names[logical_name][:depends_on] << logical_identifier(dependencies[res])
            end
          end
        end
      end

      $log.debug("Dependencies: #{JSON.pretty_generate(logical_names)}")
      return logical_names
    end

    def prove_correctness(dependencies)
      # Ensure that there are no cycles in the dependencies.
      $log.debug("Checking that there are no cycles in the dependencies...")

      if dependencies
        dependencies.each do |name,config|
          visited = [name]
          check_cycle(dependencies, name, visited)
        end
      end
    end

    def check_cycle(dependencies, resource_name, visited)
      resource_config = dependencies[resource_name]

      if resource_config.key?('depends_on')
        resource_config['depends_on'].each do |res|
          if visited.include?(res)
            $log.fatal("Dependency '#{res}' must not contain a cycle or point to itself.")
            exit(1)
          end

          visited << res
          check_cycle(dependencies, res, visited)
          # Cater for the fact that a resource can occur in multiple, separate dependency paths
          visited.pop()
        end
      end
    end

    def logical_identifier(config)
      return config['stack'] + '.' + config['resource']
    end
  end
end
