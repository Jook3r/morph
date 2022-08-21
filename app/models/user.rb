# typed: strict
# frozen_string_literal: true

# A real human being (hopefully)
class User < Owner
  extend T::Sig

  devise :trackable, :rememberable, :omniauthable, omniauth_providers: [:github]
  has_many :organizations_users, dependent: :destroy
  has_many :organizations, through: :organizations_users
  has_many :alerts, dependent: :destroy
  has_many :contributions, dependent: :destroy
  has_many :scrapers_contributed_to, through: :contributions, source: :scraper

  # In most cases people have contributed to the scrapers that they own so we
  # really don't want to see these twice. This method just removes their own
  # scrapers from the list
  sig { returns(T::Array[Scraper]) }
  def other_scrapers_contributed_to
    scrapers_contributed_to - scrapers
  end

  # A list of all owners thst this user can write to. Includes itself
  sig { returns(T::Array[Owner]) }
  def all_owners
    [self] + organizations.to_a
  end

  sig { void }
  def reset_authorization!
    a = access_token
    return if a.nil?

    update(
      access_token: Morph::Github.reset_authorization(a)
    )
  end

  # Send all alerts. This method should be run from a daily cron job
  sig { void }
  def self.process_alerts
    User.all.find_each(&:process_alerts)
  end

  sig { void }
  def process_alerts
    return if watched_broken_scrapers_ordered_by_urgency.empty?

    AlertMailer.alert_email(
      self,
      watched_broken_scrapers_ordered_by_urgency,
      watched_successful_scrapers
    ).deliver_now
  rescue Net::SMTPSyntaxError
    Rails.logger.warn "Warning: user #{nickname} has invalid email address #{email} " \
                      "(tried to send alert)"
  end

  sig { override.returns(T::Boolean) }
  def user?
    true
  end

  sig { override.returns(T::Boolean) }
  def organization?
    false
  end

  sig { params(object: T.any(Owner, Scraper)).void }
  def toggle_watch(object)
    if watching?(object)
      alerts.where(watch: object).first.destroy
    else
      # If we're starting to watch a whole bunch of scrapers (by watching a
      # user/org) and we're already following one of those scrapers individually
      # then remove the individual alert
      watch object
      if object.is_a?(Owner)
        alerts.where(watch_id: object.scrapers,
                     watch_type: "Scraper").destroy_all
      end
    end
  end

  sig { params(object: T.any(Owner, Scraper)).void }
  def watch(object)
    alerts.create(watch: object) unless watching?(object)
  end

  sig { void }
  def watch_all_owners
    all_owners.each do |object|
      watch object
    end
  end

  # Only include scrapers that finished in the last 48 hours
  sig { returns(T::Array[Scraper]) }
  def watched_successful_scrapers
    all_scrapers_watched.select do |s|
      s.finished_successfully? && s.finished_recently?
    end
  end

  sig { returns(T::Array[Scraper]) }
  def watched_broken_scrapers
    all_scrapers_watched.select do |s|
      s.finished_with_errors? && s.finished_recently?
    end
  end

  # Puts scrapers that have most recently failed first
  sig { returns(T::Array[Scraper]) }
  def watched_broken_scrapers_ordered_by_urgency
    watched_broken_scrapers.sort do |a, b|
      time_a = a.latest_successful_run_time
      time_b = b.latest_successful_run_time
      if time_b.nil? && time_a.nil?
        0
      elsif time_b.nil?
        -1
      elsif time_a.nil?
        1
      else
        T.must(time_b <=> time_a)
      end
    end
  end

  sig { returns(T::Array[Organization]) }
  def organizations_watched
    alerts.map(&:watch).select { |w| w.is_a?(Organization) }
  end

  sig { returns(T::Array[User]) }
  def users_watched
    alerts.map(&:watch).select { |w| w.is_a?(User) }
  end

  sig { returns(T::Array[Owner]) }
  def owners_watched
    alerts.map(&:watch).select { |w| w.is_a?(Owner) }
  end

  sig { returns(T::Array[Scraper]) }
  def scrapers_watched
    alerts.map(&:watch).select { |w| w.is_a?(Scraper) }
  end

  sig { returns(T::Array[Scraper]) }
  def all_scrapers_watched
    s = scrapers_watched
    owners_watched.each { |owner| s += owner.scrapers }
    s.uniq
  end

  # Are we watching this scraper because we're watching the owner
  # of the scraper?
  sig { params(scraper: Scraper).returns(T::Boolean) }
  def indirectly_watching?(scraper)
    watching?(T.must(scraper.owner))
  end

  sig { params(object: T.any(Owner, Scraper)).returns(T::Boolean) }
  def watching?(object)
    alerts.map(&:watch).include? object
  end

  sig { void }
  def refresh_organizations!
    refreshed_organizations = octokit_client.organizations(nickname).map do |data|
      org = Organization.find_or_create(data.id, data.login)
      org.refresh_info_from_github!(octokit_client)
      org
    end

    # Watch any new organizations
    (refreshed_organizations - organizations).each do |o|
      watch o
    end

    self.organizations = refreshed_organizations
  end

  sig { returns(Octokit::Client) }
  def octokit_client
    Octokit::Client.new access_token: access_token
  end

  sig { params(auth: T.untyped, _signed_in_resource: T.nilable(User)).returns(User) }
  def self.find_for_github_oauth(auth, _signed_in_resource = nil)
    user = User.find_or_create_by(provider: auth.provider, uid: auth.uid)
    user.update(nickname: auth.info.nickname,
                access_token: auth.credentials.token)
    user.refresh_info_from_github!
    # Also every time you login it should update the list of organizations that
    # the user is attached to but do this in a background job
    RefreshUserOrganizationsWorker.perform_async(T.must(user.id))
    user
  end

  sig { void }
  def refresh_info_from_github!
    user = octokit_client.user(nickname)
    update(name: user.name,
           gravatar_url: user._rels[:avatar].href,
           blog: user.blog,
           company: user.company,
           location: user.location,
           email: Morph::Github.primary_email(self))
  rescue Octokit::Unauthorized, Octokit::NotFound
    false
  end

  sig { params(nickname: String).returns(User) }
  def self.find_or_create_by_nickname(nickname)
    u = User.find_by(nickname: nickname)
    if u.nil?
      u = User.create(nickname: nickname)
      u.refresh_info_from_github!
    end
    u
  end

  sig { returns(T::Boolean) }
  def active_for_authentication?
    !suspended?
  end

  # TODO: Move this to locale
  sig { returns(String) }
  def inactive_message
    "Your account has been suspended. " \
      "Please contact us if you think this is in error."
  end

  sig { returns(T::Boolean) }
  def never_alerted?
    alerted_at.blank?
  end
end
