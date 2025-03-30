# OutboxNotifier is a lightweight signaling mechanism
# to notify a single background thread (e.g. OutboxWorker)
# that new data is available and it should wake up to process it.
#
# This implementation avoids memory leaks and signal flooding:
# - If notify! is called multiple times before the thread calls wait,
#   only one notification is remembered (no queue buildup).
# - If notify! is called when no thread is waiting, the signal is not lost.
# - The next call to wait will return immediately.

class OutboxNotifier
  @mutex = Mutex.new
  @condition = ConditionVariable.new
  @notified = false

  class << self
    # Called by producers (e.g. the processor) to notify the waiting thread
    def notify!
      @mutex.synchronize do
        # Set flag so that even if no thread is waiting,
        # the next wait will return immediately
        @notified = true

        # Wake up a single waiting thread, if any
        @condition.signal
      end
    end

    # Called by the background worker to block until a notification is received
    def wait
      @mutex.synchronize do
        # If already notified, don't block
        @condition.wait(@mutex) until @notified

        # Reset flag so next wait will block again
        @notified = false
      end
    end
  end
end
