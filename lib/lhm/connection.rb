require 'delegate'
require 'lhm/sql_retry'

module Lhm
  class Connection < SimpleDelegator

    # Lhm::Connection inherits from SingleDelegator. It will forward any unknown method calls to the ActiveRecord
    # connection.
    alias connection __getobj__
    alias connection= __setobj__

    def initialize(connection:, default_log_prefix: nil, options: {}, retry_config: {})
      @default_log_prefix = default_log_prefix
      @retry_options = retry_config || default_retry_config
      @sql_retry = Lhm::SqlRetry.new(
        connection,
        options: retry_config,
        reconnect_with_consistent_host: options[:reconnect_with_consistent_host] || false
      )

      # Creates delegation for the ActiveRecord Connection
      super(connection)
    end

    def options=(options)
      # If any other flags are added. Add the "processing" here
      @sql_retry.reconnect_with_consistent_host = options[:reconnect_with_consistent_host] || false
    end

    def execute(query, should_retry: false, retry_options: {})
      if should_retry
        exec_with_retries(:execute, query, retry_options)
      else
        exec(:execute, query)
      end
    end

    def update(query, should_retry: false, retry_options: {})
      if should_retry
        exec_with_retries(:update, query, retry_options)
      else
        exec(:update, query)
      end
    end

    def select_value(query, should_retry: false, retry_options: {})
      if should_retry
        exec_with_retries(:select_value, query, retry_options)
      else
        exec(:select_value, query)
      end
    end

    def select_values(query, should_retry: false, retry_options: {})
      if should_retry
        exec_with_retries(:select_values, query, retry_options)
      else
        exec(:select_values, query)
      end
    end

    def select_one(query, should_retry: false, retry_options: {})
      if should_retry
        exec_with_retries(:select_one, query, retry_options)
      else
        exec(:select_one, query)
      end
    end

    private

    def exec(method, sql)
      connection.public_send(method, Lhm::ProxySQLHelper.tagged(sql))
    end

    def exec_with_retries(method, sql, retry_options = {})
      retry_options[:log_prefix] ||= file
      @sql_retry.with_retries(retry_options) do |conn|
        conn.public_send(method, Lhm::ProxySQLHelper.tagged(sql))
      end
    end

    # Returns camelized file name of caller (e.g. chunk_insert.rb -> ChunkInsert)
    def file
      # Find calling file and extract name
      /[\/]*(\w+).rb:\d+:in/.match(relevant_caller)
      name = $1&.camelize || "Connection"
      "#{name}"
    end

    def relevant_caller
      lhm_stack = caller.select { |x| x.include?("/lhm") }
      first_candidate_index = lhm_stack.find_index { |line| !line.include?(__FILE__) }

      # Find the file that called the `#execute` (fallbacks to current file)
      return lhm_stack.first unless first_candidate_index
      lhm_stack.at(first_candidate_index)
    end
  end
end