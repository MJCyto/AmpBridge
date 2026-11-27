ExUnit.start()

# Mix starts the application before loading tests. Keeping startup here too
# creates duplicate named processes and concurrent SQLite writers.
