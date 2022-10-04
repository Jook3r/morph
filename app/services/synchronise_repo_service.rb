# typed: strict
# frozen_string_literal: true

class SynchroniseRepoService
  extend T::Sig

  # Says that the morph github app has not been installed on the user or organization
  class NoAppInstallationForOwner < StandardError; end

  # Returns true if successfull
  # TODO: Return more helpful error messages
  sig { params(scraper: Scraper).returns(T::Boolean) }
  def self.call(scraper)
    url, error = git_url_https_with_app_access(scraper)
    case error
    when NoAppInstallationForOwner
      raise NoAppInstallationForOwner
    when nil
      nil
    else
      T.absurd(error)
    end

    success = Morph::Github.synchronise_repo(scraper.repo_path, url)
    return false unless success

    update_repo_size(scraper)
    update_contributors(scraper)
    true
  end

  # This is all a bit hacky
  # TODO: Tidy up
  sig { params(scraper: Scraper).returns([String, T.nilable(NoAppInstallationForOwner)]) }
  def self.git_url_https_with_app_access(scraper)
    token = Morph::Github.app_installation_access_token(T.must(T.must(scraper.owner).nickname))
    return ["", NoAppInstallationForOwner.new] if token.nil?

    url = scraper.git_url_https.sub("https://", "https://x-access-token:#{token}@")
    [url, nil]
  end

  sig { params(scraper: Scraper).void }
  def self.update_repo_size(scraper)
    scraper.update!(repo_size: directory_size(scraper.repo_path))
  end

  sig { params(scraper: Scraper).void }
  def self.update_contributors(scraper)
    nicknames = Morph::Github.contributor_nicknames(T.must(T.must(scraper.owner).nickname), scraper.name)
    contributors = nicknames.map { |n| User.find_or_create_by_nickname(n) }
    # TODO: Use update! here?
    scraper.update(contributors: contributors)
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
               directory_size(f)
             end
      end
    end
    r
  end
end
