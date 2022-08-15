# typed: true
# frozen_string_literal: true

# A scraper is a script that runs that gets data from the web
class Scraper < ApplicationRecord
  extend T::Sig

  include RenderSync::Actions
  # Using smaller batch_size than the default for the time being because
  # reindexing causes elasticsearch on the local VM to run out of memory
  # defaults to 1000
  searchkick word_end: [:scraped_domain_names], word_middle: [:full_name],
             batch_size: 100

  belongs_to :owner, inverse_of: :scrapers
  belongs_to :forked_by, class_name: "User", optional: true

  has_many :runs, inverse_of: :scraper, dependent: :destroy
  has_one :last_run, -> { order "queued_at DESC" }, class_name: "Run", dependent: :destroy, inverse_of: :scraper
  has_many :metrics, through: :runs
  has_many :contributions, dependent: :delete_all
  has_many :contributors, through: :contributions, source: :user
  has_many :watches, class_name: "Alert", foreign_key: :watch_id, dependent: :delete_all, inverse_of: :watch
  has_many :watchers, through: :watches, source: :user
  belongs_to :create_scraper_progress, dependent: :delete, optional: true
  has_many :variables, dependent: :delete_all
  accepts_nested_attributes_for :variables, allow_destroy: true
  has_many :webhooks, dependent: :destroy
  accepts_nested_attributes_for :webhooks, allow_destroy: true
  validates_associated :variables
  delegate :sqlite_total_rows, to: :database

  has_many :api_queries, dependent: :delete_all

  validates :name, presence: true, format: {
    with: /\A[a-zA-Z0-9_-]+\z/,
    message: "can only have letters, numbers, '_' and '-'"
  }
  validates :name, uniqueness: {
    scope: :owner, message: "is already taken on morph.io"
  }
  validate :not_used_on_github, on: :create, if: proc { |s| s.github_id.blank? && s.name.present? }

  extend FriendlyId
  friendly_id :full_name

  delegate :finished_recently?, :finished_at, :finished_successfully?,
           :finished_with_errors?, :queued?, :running?, :stop!,
           to: :last_run, allow_nil: true

  sig { returns(T::Array[Scraper]) }
  def self.running
    Run.running.map(&:scraper).compact
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def search_data
    {
      full_name: full_name,
      description: description,
      scraped_domain_names: scraped_domain_names,
      data?: data?
    }
  end

  sig { returns(T::Boolean) }
  def data?
    sqlite_total_rows.positive?
  end

  sig { returns(T::Array[String]) }
  def scraped_domain_names
    scraped_domains.map(&:name)
  end

  sig { returns(T.any(ActiveRecord::Associations::CollectionProxy, [])) }
  def scraped_domains
    last_run&.domains || []
  end

  sig { returns(T::Array[User]) }
  def all_watchers
    owner_watchers = (owner&.watchers || [])
    (watchers + owner_watchers).uniq
  end

  # Also orders the owners by number of downloads
  sig { returns(T::Array[[Owner, Integer]]) }
  def download_count_by_owner
    # TODO: Simplify this by using an association on api_query
    count_by_owner_id = api_queries
                        .group(:owner_id)
                        .order("count_all desc")
                        .count
    count_by_owner_id.map do |id, count|
      [Owner.find(id), count]
    end
  end

  sig { returns(Integer) }
  def download_count
    api_queries.count
  end

  # Given a scraper name on github populates the fields for a morph.io scraper
  # but doesn't save it
  sig { params(full_name: String, octokit_client: Octokit::Client).returns(Scraper) }
  def self.new_from_github(full_name, octokit_client)
    repo = octokit_client.repository(full_name)
    repo_owner = Owner.find_by!(nickname: repo.owner.login)
    # Populate a new scraper with information from the repo
    Scraper.new(
      name: repo.name, full_name: repo.full_name, description: repo.description,
      github_id: repo.id, owner_id: repo_owner.id,
      github_url: repo.rels[:html].href, git_url: repo.rels[:git].href
    )
  end

  sig { returns(T.nilable(Morph::Language)) }
  def original_language
    o = original_language_key
    Morph::Language.new(o.to_sym) if o
  end

  sig { void }
  def update_contributors
    nicknames = Morph::Github.contributor_nicknames(full_name)
    contributors = nicknames.map { |n| User.find_or_create_by_nickname(n) }
    update(contributors: contributors)
  end

  sig { returns(ActiveRecord::AssociationRelation) }
  def successful_runs
    runs.order(finished_at: :desc).finished_successfully
  end

  sig { returns(T.nilable(Time)) }
  def latest_successful_run_time
    latest_successful_run = successful_runs.first
    latest_successful_run&.finished_at
  end

  sig { returns(ActiveRecord::AssociationRelation) }
  def finished_runs
    runs.where.not(finished_at: nil).order(finished_at: :desc)
  end

  # For successful runs calculates the average wall clock time that this scraper
  # takes. Handy for the user to know how long it should expect to run for
  # Returns nil if not able to calculate this
  # TODO: Refactor this using scopes
  sig { returns(T.nilable(Float)) }
  def average_successful_wall_time
    return if successful_runs.count.zero?

    successful_runs.sum(:wall_time) / successful_runs.count
  end

  sig { returns(Float) }
  def total_wall_time
    runs.to_a.sum(&:wall_time)
  end

  sig { returns(Float) }
  def utime
    metrics.sum(:utime)
  end

  sig { returns(Float) }
  def stime
    metrics.sum(:stime)
  end

  sig { returns(Float) }
  def cpu_time
    utime + stime
  end

  sig { void }
  def update_sqlite_db_size
    update(sqlite_db_size: database.sqlite_db_size)
  end

  sig { returns(Integer) }
  def total_disk_usage
    repo_size + sqlite_db_size
  end

  # Let's say a scraper requires attention if it's set to run automatically and
  # the last run failed
  # TODO: This is now inconsistent with the way this is handled elsewhere
  sig { returns(T::Boolean) }
  def requires_attention?
    auto_run && last_run&.finished_with_errors?
  end

  sig { void }
  def destroy_repo_and_data
    FileUtils.rm_rf repo_path
    FileUtils.rm_rf data_path
  end

  sig { returns(String) }
  def repo_path
    "#{owner&.repo_root}/#{name}"
  end

  sig { returns(String) }
  def data_path
    "#{owner&.data_root}/#{name}"
  end

  sig { returns(T.nilable(String)) }
  def readme
    f = Dir.glob(File.join(repo_path, "README*")).first
    # rubocop:disable Rails/OutputSafety
    GitHub::Markup.render(f, File.read(f)).html_safe if f
    # rubocop:enable Rails/OutputSafety
  end

  sig { returns(String) }
  def readme_filename
    Pathname.new(Dir.glob(File.join(repo_path, "README*")).first).basename.to_s
  end

  sig { returns(String) }
  def github_url_readme
    github_url_for_file(readme_filename)
  end

  sig { returns(T::Boolean) }
  def runnable?
    l = last_run
    l.nil? || l.finished?
  end

  sig { void }
  def queue!
    # Guard against more than one of a particular scraper running at the
    # same time
    return unless runnable?

    run = runs.create(queued_at: Time.zone.now, auto: false, owner_id: owner_id)
    RunWorker.perform_async(run.id)
  end

  # If repo is still using the old "master" branch name then the url below will
  # just redirect to master, because it's the default branch
  sig { params(file: String).returns(String) }
  def github_url_for_file(file)
    "#{github_url}/blob/main/#{file}"
  end

  sig { returns(T.nilable(Morph::Language)) }
  def language
    Morph::Language.language(repo_path)
  end

  sig { returns(T.nilable(String)) }
  def main_scraper_filename
    language&.scraper_filename
  end

  sig { returns(T.nilable(String)) }
  def github_url_main_scraper_file
    m = main_scraper_filename
    github_url_for_file(m) if m
  end

  sig { returns(Morph::Database) }
  def database
    Morph::Database.new(data_path)
  end

  sig { returns(T.nilable(String)) }
  def platform
    platform_file = "#{repo_path}/platform"
    platform = File.read(platform_file).chomp if File.exist?(platform_file)
    # TODO: We should remove support for early_release at some stage
    platform = "heroku-18" if platform == "early_release"
    platform
  end

  # It seems silly implementing this
  sig { params(directory: String).returns(Integer) }
  def self.directory_size(directory)
    r = 0
    if File.exist?(directory)
      # Ick
      files = Dir.entries(directory)
      files.delete(".")
      files.delete("..")
      files.map { |f| File.join(directory, f) }.each do |f|
        s = File.lstat(f)
        r += if s.file?
               s.size
             else
               Scraper.directory_size(f)
             end
      end
    end
    r
  end

  sig { void }
  def update_repo_size
    update_attribute(:repo_size, Scraper.directory_size(repo_path))
  end

  sig { returns(String) }
  def current_revision_from_repo
    r = Grit::Repo.new(repo_path)
    Grit::Head.current(r).commit.id
  end

  # files should be a hash of "filename" => "content"
  def add_commit_to_main_on_github(user, files, message)
    client = user.octokit_client
    blobs = files.map do |filename, content|
      {
        path: filename,
        mode: "100644",
        type: "blob",
        content: content
      }
    end

    # Let's get all the info about head
    ref = client.ref(full_name, "heads/main")
    commit_sha = ref.object.sha
    commit = client.commit(full_name, commit_sha)
    tree_sha = commit.commit.tree.sha

    tree2 = client.create_tree(full_name, blobs, base_tree: tree_sha)
    commit2 = client.create_commit(full_name, message, tree2.sha, commit_sha)
    client.update_ref(full_name, "heads/main", commit2.sha)
  end

  # Overwrites whatever there was before in that repo
  # Obviously use with great care
  sig { params(user: User, files: T::Hash[String, String], message: String).void }
  def add_commit_to_root_on_github(user, files, message)
    client = user.octokit_client
    blobs = files.map do |filename, content|
      {
        path: filename,
        mode: "100644",
        type: "blob",
        content: content
      }
    end
    tree = client.create_tree(full_name, blobs)
    commit = client.create_commit(full_name, message, tree.sha)
    client.update_ref(full_name, "heads/main", commit.sha)
  end

  # Returns true if successfull
  sig { returns(T::Boolean) }
  def synchronise_repo
    success = Morph::Github.synchronise_repo(repo_path, git_url_https)
    return false unless success

    update_repo_size
    update_contributors
    true
  rescue Grit::Git::CommandFailed => e
    Rails.logger.error "git command failed: #{e}"
    Rails.logger.error "Ignoring and moving onto the next one..."
    false
  end

  # Return the https version of the git clone url (git_url)
  def git_url_https
    url = git_url
    "https#{url[3..-1]}" if url
  end

  def deliver_webhooks(run)
    webhooks.each do |webhook|
      webhook_delivery = webhook.deliveries.create!(run: run)
      DeliverWebhookWorker.perform_async(webhook_delivery.id)
    end
  end

  private

  def not_used_on_github
    return unless Octokit.client.repository?(full_name)

    errors.add(:name, "is already taken on GitHub")
  end
end
