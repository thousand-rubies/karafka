# frozen_string_literal: true

# When there is a misconfiguration of karafka options on ActiveJob job class, it should raise an
# error

setup_karafka do |config|
  config.license.token = pro_license_token
end

setup_active_job

def handle
  yield
  DT[0] << false
rescue Karafka::Errors::InvalidConfigurationError
  DT[0] << true
end

Job = Class.new(ActiveJob::Base)

class Partitioner
  def call(_job)
    rand
  end
end

NotPartitioner = Class.new

handle { Job.karafka_options(dispatch_method: :na) }
handle { Job.karafka_options(dispatch_method: :produce_async) }
handle { Job.karafka_options(dispatch_method: rand) }
handle { Job.karafka_options(partitioner: rand) }
handle { Job.karafka_options(partitioner: ->(job) { job.job_id }) }
handle { Job.karafka_options(partitioner: Partitioner.new) }
handle { Job.karafka_options(partitioner: NotPartitioner.new) }

assert DT[0][0]
assert_equal false, DT[0][1]
assert DT[0][2]
assert DT[0][3]
assert_equal false, DT[0][4]
assert_equal false, DT[0][5]
assert DT[0][6]
