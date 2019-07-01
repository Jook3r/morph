# frozen_string_literal: true

require "spec_helper"

RSpec.describe Webhook, type: :model do
  describe "#url" do
    it "should require a url" do
      webhook = Webhook.new
      expect(webhook).to_not be_valid
      expect(webhook.errors.keys).to eq([:url])
    end

    it "should not allow duplicate webhooks for the same scraper" do
      owner = Owner.create!
      scraper = Scraper.create!(name: "scraper", owner: owner)
      Webhook.create!(scraper: scraper, url: "https://example.org")

      expect(Webhook.new(scraper: scraper, url: "https://example.org")).to_not be_valid
    end

    it "should not be an invalid URL" do
      w = Webhook.new(url: "foo bar")

      expect(w).to_not be_valid
      expect(w.errors[:url]).to include "is not a valid URL"
    end
  end

  describe "#last_delivery" do
    it "should return the most recently sent delivery" do
      webhook = Webhook.create!(url: "https://example.org")
      delivery1 = webhook.deliveries.create!(created_at: 3.hours.ago, sent_at: 1.hour.ago)
      webhook.deliveries.create!(created_at: 2.hours.ago, sent_at: 2.hours.ago)
      expect(webhook.last_delivery).to eq(delivery1)
    end
  end
end
