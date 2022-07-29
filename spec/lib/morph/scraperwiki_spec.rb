# frozen_string_literal: true

require "spec_helper"

describe Morph::Scraperwiki do
  describe "#sqlite_database" do
    it "gets the scraperwiki sqlite database via their api" do
      result = double
      expect(described_class).to receive(:content).with("https://classic.scraperwiki.com/scrapers/export_sqlite/blue-mountains.sqlite").and_return(result)

      s = described_class.new("blue-mountains")
      expect(s.sqlite_database).to eq result
    end

    it "raises an exception if the dataproxy connection time out" do
      result = "The dataproxy connection timed out, please retry. This is why."
      expect(described_class).to receive(:content).with("https://classic.scraperwiki.com/scrapers/export_sqlite/blue-mountains.sqlite").and_return(result)

      s = described_class.new("blue-mountains")
      expect { s.sqlite_database }.to raise_error result
    end
  end

  describe ".content" do
    it "grabs the contents of a url" do
      response = double
      data = double
      expect(Faraday).to receive(:get).with("http://foo.com").and_return(response)
      expect(response).to receive(:body).and_return(data)
      expect(response).to receive(:success?).and_return(true)
      expect(described_class.content("http://foo.com")).to eq data
    end
  end

  describe "#exists?" do
    it { expect(described_class.new(nil).exists?).not_to be_truthy }
    it { expect(described_class.new("").exists?).not_to be_truthy }

    it "says non existent scrapers don't exist" do
      VCR.use_cassette("scraperwiki") do
        expect(described_class.new("non_existent_scraper").exists?).not_to be_truthy
      end
    end
  end
end
