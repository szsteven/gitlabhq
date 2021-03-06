# frozen_string_literal: true

require 'spec_helper'

describe Gitlab::CycleAnalytics::ProductionEventFetcher do
  let(:stage_name) { :production }

  it_behaves_like 'default query config'
end
