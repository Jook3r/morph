# typed: false
# frozen_string_literal: true

require "spec_helper"
require "cancan/matchers"

describe "User" do
  describe "abilities" do
    subject(:ability) { Ability.new(user) }

    let(:user) { nil }
    let(:scraper) do
      VCR.use_cassette("scraper_validations", allow_playback_repeats: true) do
        create(:scraper)
      end
    end
    let(:organization) { create(:organization) }
    let(:other_user) { create(:user) }

    context "when an unauthenticated user" do
      # Scraper
      # Can
      it { is_expected.to be_able_to(:index, Scraper) }
      it { is_expected.to be_able_to(:running, Scraper) }
      it { is_expected.to be_able_to(:show, scraper) }
      it { is_expected.to be_able_to(:watchers, scraper) }
      it { is_expected.to be_able_to(:history, scraper) }

      # Can not
      it { is_expected.not_to be_able_to(:new, Scraper) }
      it { is_expected.not_to be_able_to(:create, Scraper) }
      it { is_expected.not_to be_able_to(:github, Scraper) }
      it { is_expected.not_to be_able_to(:github_form, Scraper) }
      it { is_expected.not_to be_able_to(:create_github, Scraper) }

      it { is_expected.not_to be_able_to(:settings, scraper) }
      it { is_expected.not_to be_able_to(:destroy, scraper) }
      it { is_expected.not_to be_able_to(:update, scraper) }
      it { is_expected.not_to be_able_to(:run, scraper) }
      it { is_expected.not_to be_able_to(:stop, scraper) }
      it { is_expected.not_to be_able_to(:clear, scraper) }
      it { is_expected.not_to be_able_to(:watch, scraper) }

      # Organization
      # Can
      it { is_expected.to be_able_to(:show, organization) }

      # Can not
      it { is_expected.not_to be_able_to(:settings, organization) }
      it { is_expected.not_to be_able_to(:settings_redirect, organization) }
      it { is_expected.not_to be_able_to(:reset_key, organization) }
      it { is_expected.not_to be_able_to(:watch, organization) }

      # User
      # Can
      it { is_expected.to be_able_to(:index, User) }
      it { is_expected.to be_able_to(:stats, User) }
      it { is_expected.to be_able_to(:watching, other_user) }
      it { is_expected.to be_able_to(:show, other_user) }

      # Can not
      it { is_expected.not_to be_able_to(:settings, other_user) }
      it { is_expected.not_to be_able_to(:settings_redirect, other_user) }
      it { is_expected.not_to be_able_to(:reset_key, other_user) }
      it { is_expected.not_to be_able_to(:watch, other_user) }

      # SiteSetting
      # Can not
      it { is_expected.not_to be_able_to(:toggle_read_only_mode, SiteSetting) }
      it { is_expected.not_to be_able_to(:update_maximum_concurrent_scrapers, SiteSetting) }

      # Run
      it { is_expected.not_to be_able_to(:create, Run) }
    end

    context "when a regular authenticated user" do
      let(:user) { create(:user) }

      # Scraper
      # Can
      it { is_expected.to be_able_to(:index, Scraper) }
      it { is_expected.to be_able_to(:running, Scraper) }
      it { is_expected.to be_able_to(:show, scraper) }
      it { is_expected.to be_able_to(:watchers, scraper) }
      it { is_expected.to be_able_to(:history, scraper) }
      it { is_expected.to be_able_to(:new, Scraper) }
      it { is_expected.to be_able_to(:create, Scraper) }
      it { is_expected.to be_able_to(:github, Scraper) }
      it { is_expected.to be_able_to(:github_form, Scraper) }
      it { is_expected.to be_able_to(:create_github, Scraper) }

      # Can not
      it { is_expected.not_to be_able_to(:settings, scraper) }
      it { is_expected.not_to be_able_to(:destroy, scraper) }
      it { is_expected.not_to be_able_to(:update, scraper) }
      it { is_expected.not_to be_able_to(:run, scraper) }
      it { is_expected.not_to be_able_to(:stop, scraper) }
      it { is_expected.not_to be_able_to(:clear, scraper) }
      it { is_expected.not_to be_able_to(:watch, scraper) }

      context "when scraper is owner by the user" do
        before do
          scraper.update(owner: user)
        end

        it { is_expected.to be_able_to(:settings, scraper) }
        it { is_expected.to be_able_to(:destroy, scraper) }
        it { is_expected.to be_able_to(:update, scraper) }
        it { is_expected.to be_able_to(:run, scraper) }
        it { is_expected.to be_able_to(:stop, scraper) }
        it { is_expected.to be_able_to(:clear, scraper) }
        it { is_expected.not_to be_able_to(:watch, scraper) }
      end

      context "when scraper is owned by an organization the user is a member of" do
        before do
          scraper.update(owner: organization)
          create(:organizations_user, organization: organization, user: user)
        end

        it { is_expected.to be_able_to(:settings, scraper) }
        it { is_expected.to be_able_to(:destroy, scraper) }
        it { is_expected.to be_able_to(:update, scraper) }
        it { is_expected.to be_able_to(:run, scraper) }
        it { is_expected.to be_able_to(:stop, scraper) }
        it { is_expected.to be_able_to(:clear, scraper) }
        it { is_expected.not_to be_able_to(:watch, scraper) }
      end

      # Organization
      # Can
      it { is_expected.to be_able_to(:show, organization) }
      it { is_expected.to be_able_to(:watch, organization) }
      it { is_expected.to be_able_to(:settings_redirect, organization) }

      # Can not
      it { is_expected.not_to be_able_to(:settings, organization) }
      it { is_expected.not_to be_able_to(:reset_key, organization) }

      context "when the organization has the user as a member" do
        before do
          create(:organizations_user, organization: organization, user: user)
        end

        # Organization
        # Can
        it { is_expected.to be_able_to(:show, organization) }
        it { is_expected.to be_able_to(:watch, organization) }
        it { is_expected.to be_able_to(:settings, organization) }
        it { is_expected.to be_able_to(:settings_redirect, Organization) }
        it { is_expected.to be_able_to(:reset_key, organization) }
      end

      # User
      # Can
      it { is_expected.to be_able_to(:index, User) }
      it { is_expected.to be_able_to(:stats, User) }
      it { is_expected.to be_able_to(:watching, other_user) }
      it { is_expected.to be_able_to(:show, other_user) }
      it { is_expected.to be_able_to(:settings_redirect, User) }
      it { is_expected.to be_able_to(:watch, other_user) }

      # Can not
      it { is_expected.not_to be_able_to(:settings, other_user) }
      it { is_expected.not_to be_able_to(:reset_key, other_user) }

      # SiteSetting
      # Can not
      it { is_expected.not_to be_able_to(:toggle_read_only_mode, SiteSetting) }
      it { is_expected.not_to be_able_to(:update_maximum_concurrent_scrapers, SiteSetting) }

      # Run
      it { is_expected.to be_able_to(:create, Run) }
    end
  end
end
