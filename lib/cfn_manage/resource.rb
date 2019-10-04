class Resource
  attr_accessor :id, :priority, :type, :dependencies, :available, :configuration, :execution_state

  def initialize(id:, priority:, type:)
    @id = id
    @priority = priority
    @type = type
    @available = false
    @dependencies = []
    @configuration = {}
    @execution_state = ExecutionStates::None
  end
end