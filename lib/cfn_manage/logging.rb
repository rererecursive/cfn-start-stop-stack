require 'logger'

$log = Logger.new(STDOUT)

def fatal_exit(message)
  $log.fatal(message)
  exit(1)
end
