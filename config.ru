require_relative 'lib/app'

Thread.new do
  loop do
    sleep 60
    Buffer.replay
  end
end

run App
