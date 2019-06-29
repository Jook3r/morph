module Morph
  # Service layer for talking to Scraperwiki
  class Scraperwiki
    attr_reader :short_name

    def initialize(short_name)
      @short_name = short_name
    end

    def sqlite_database
      if @sqlite_database.nil?
        content = Morph::Scraperwiki.content(
          'https://classic.scraperwiki.com/scrapers/export_sqlite/' \
          "#{short_name}.sqlite"
        )
        if content =~ /The dataproxy connection timed out, please retry/
          raise content
        end

        @sqlite_database = content
      end
      @sqlite_database
    end

    def info
      raise 'short_name not set' if short_name.blank?

      if @info.nil?
        url = "https://classic.scraperwiki.com/scrapers/#{short_name}/info.json"
        content = Morph::Scraperwiki.content(url)
        v = JSON.parse(content) unless content.blank?
        if v.nil? ||
           (v.is_a?(Hash) && v['error'] == 'Sorry, this scraper does not exist')
          @info = nil
        else
          @info = v.first
        end
      end
      @info
    end

    def translated_code
      Morph::CodeTranslate.translate(language.key, code)
    end

    def exists?
      !short_name.blank? && !!info
    end

    def view?
      language.key == :html
    end

    def private_scraper?
      exists? && info && info.key?('error') &&
        info['error'] == 'Invalid API Key'
    end

    def code
      info['code']
    end

    def title
      info['title']
    end

    def description
      info['description']
    end

    def language
      if exists? && info && info.key?('language')
        Morph::Language.new(info['language'].to_sym)
      else
        Morph::Language.new(nil)
      end
    end

    def self.content(url)
      a = Faraday.get(url)
      a.body if a.success?
    end
  end
end
