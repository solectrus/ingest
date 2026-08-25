# Puma reads this file on its own, so `rackup` picks it up too.

# The pool of ActiveRecord gets its size from the same variable, see
# Database.pool_size. Without this file, the variable changed the pool only,
# and Puma kept its default of 5 threads.
threads_count = ENV.fetch('PUMA_THREADS', 5).to_i
threads threads_count, threads_count

# Single mode, on purpose. The boot in config.ru runs the migrations and starts
# the OutboxWorker and the CleanupWorker. A fork would run the migrations twice
# and give every worker its own copy of the two threads.
workers 0
