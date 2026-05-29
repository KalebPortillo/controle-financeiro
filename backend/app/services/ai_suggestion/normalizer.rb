module AiSuggestion
  module Normalizer
    CPF_PATTERN    = /\d{3}\.\d{3}\.\d{3}-\d{2}/.freeze
    DATE_PATTERN   = /\b\d{2}\/\d{2}(\/\d{2,4})?\b/.freeze
    LONG_NUM       = /\b\d{5,}\b/.freeze
    ASTERISK_GLOB  = /\*/.freeze

    def self.call(raw)
      raw.to_s
         .gsub(CPF_PATTERN,   " ")
         .gsub(DATE_PATTERN,  " ")
         .gsub(LONG_NUM,      " ")
         .gsub(ASTERISK_GLOB, " ")
         .downcase
         .gsub(/[^a-záéíóúàâêôãõüç\d\s]/i, " ")
         .gsub(/\s+/, " ")
         .strip
    end
  end
end
