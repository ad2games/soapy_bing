# frozen_string_literal: true

require 'date'

RSpec.describe SoapyBing::Ads::CampaignPerformanceReport do
  subject(:report) { described_class.new(report_options) }

  let(:report_options) do
    {
      service_options: {},
      date_start: date_start,
      date_end: date_end,
      polling_settings: polling_settings
    }
  end
  let(:polling_settings) { {} }
  let(:service_double) { double }

  describe '#initialize' do
    context 'when there is a wrong date format' do
      let(:date_start) { 'wrong_date' }
      let(:date_end) { 'today' }

      it 'throws exception' do
        expect { report }.to raise_error(ArgumentError, 'invalid date')
      end
    end

    context 'with valid dates' do
      let(:date_start) { '2017-06-20' }
      let(:date_end) { '2017-06-21' }

      it 'sets default pooling settings' do
        polling_settings = report.polling_settings
        expect(polling_settings[:tries]).to eq(20)
        expect(polling_settings[:sleep].call(6)).to eq(64)
        expect(polling_settings[:sleep].call(7)).to eq(120)
      end
    end
  end

  describe '#rows' do
    let(:date_start) { '2016-09-15' }
    let(:date_end) { '2016-09-15' }

    before do
      allow(SoapyBing::Service).to receive(:reporting).and_return(service_double)
      allow(service_double).to receive(:submit_generate_report).and_return(report_request_id: '123')
      allow(service_double).to receive(:poll_generate_report) do
        {
          report_request_status: { status: status }
        }
      end
    end

    context 'with pending response' do
      let(:polling_settings) { { tries: 3, sleep: 0 } }
      let(:status) { 'Pending' }

      it 'raises NotCompleted' do
        expect { report.rows }.to raise_error SoapyBing::Ads::NotCompleted
        expect(service_double).to have_received(:submit_generate_report).once
        expect(service_double).to have_received(:poll_generate_report).exactly(3).times
      end
    end

    context 'with failed response' do
      let(:status) { 'Error' }

      it 'raises StatusFailed' do
        expect { report.rows }.to raise_error SoapyBing::Ads::StatusFailed
        expect(service_double).to have_received(:submit_generate_report).once
        expect(service_double).to have_received(:poll_generate_report).once
      end
    end
  end
end
