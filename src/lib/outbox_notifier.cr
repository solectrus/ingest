# OutboxNotifier is a lightweight signaling mechanism
# to notify a single background fiber (e.g. OutboxWorker)
# that new data is available and it should wake up to process it.
#
# This implementation uses Crystal's Channel for fiber communication.

class OutboxNotifier
  @@channel = Channel(Nil).new(1)

  def self.notify!
    # Try to send a signal, but don't block if channel is full
    # This prevents flooding the channel with notifications
    select
    when @@channel.send(nil)
      # Signal sent
    else
      # Channel full, skip (a notification is already pending)
    end
  end

  def self.wait
    # Block until a notification is received
    @@channel.receive
  end
end
