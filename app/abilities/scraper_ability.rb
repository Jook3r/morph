# typed: strict
# frozen_string_literal: true

class ScraperAbility
  extend T::Sig

  include CanCan::Ability

  sig { params(user: T.nilable(User)).void }
  def initialize(user)
    # Everyone can list all the scrapers
    can %i[index show watchers running history], Scraper

    return unless user

    # user can view settings of scrapers it owns
    can :settings, Scraper, owner_id: user.id

    unless SiteSetting.read_only_mode
      can %i[destroy update run stop clear create create_github],
          Scraper,
          owner_id: user.id
    end

    # user can view settings of scrapers belonging to an org they are a
    # member of
    user.organizations.each do |org|
      can :settings, Scraper, owner_id: org.id
      next if SiteSetting.read_only_mode

      can %i[destroy update run stop clear create create_github],
          Scraper,
          owner_id: org.id
    end

    can %i[new github github_form watch], Scraper unless SiteSetting.read_only_mode

    return unless user.admin?

    # Admins also have the special power to update the memory setting and increase the memory available to the scraper
    can :memory_setting, Scraper
  end
end
