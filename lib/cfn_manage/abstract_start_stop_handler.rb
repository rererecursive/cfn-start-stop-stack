module CfnManage

  class AbstractStartStopHandler

    def start(resource, run_configuration)
      return true
    end

    def post_start(resource, run_configuration)
      return true
    end

    def stop(resource, run_configuration)
      return true
    end

    def post_stop(resource, run_configuration)
      return true
    end

    def check_health(resource, run_configuration)
      return true
    end

  end

end
