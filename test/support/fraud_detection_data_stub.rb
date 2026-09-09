# Swaps in a stand-in for the secrets submodule's detection-data unpacker for
# the duration of a block.
#
# Two reasons the tests don't use the real one: the submodule isn't always
# checked out, and its metric names are deliberately absent from this repo, so
# a test that asserted on them would put them back.
module FraudDetectionDataStub
  def with_detection_data(rows)
    namespace = fraud_namespace
    original = namespace.const_get(:FraudDetectionData) if namespace.const_defined?(:FraudDetectionData, false)
    namespace.send(:remove_const, :FraudDetectionData) if original

    stub = Module.new
    stub.define_singleton_method(:unpack) { |_data| rows }
    namespace.const_set(:FraudDetectionData, stub)

    yield
  ensure
    namespace.send(:remove_const, :FraudDetectionData) if namespace.const_defined?(:FraudDetectionData, false)
    namespace.const_set(:FraudDetectionData, original) if original
    Certification.send(:remove_const, :Fraud) if @fraud_namespace_created
  end

  private

  def fraud_namespace
    return Certification::Fraud if defined?(Certification::Fraud)

    @fraud_namespace_created = true
    Certification.const_set(:Fraud, Module.new)
  end
end
