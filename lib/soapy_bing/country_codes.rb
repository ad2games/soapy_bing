# frozen_string_literal: true

require 'yaml'

module SoapyBing
  class CountryCodes
    YML_FILE_PATH = File.join(__dir__, 'country_codes.yml').freeze

    def initialize
      @country_codes = YAML.safe_load(File.read(YML_FILE_PATH))
    end

    def code(id)
      @country_codes.fetch(id.to_s)
    end
  end
end
