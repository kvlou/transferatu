# Silencing rollbar
Rollbar.configure do |c|
  c.enabled = false
  c.logger = Logger.new(File::NULL)
end
