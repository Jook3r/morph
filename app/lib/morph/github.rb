# typed: strict
# frozen_string_literal: true

module Morph
  # Service layer for talking to the Github API. Acts on behalf of a user
  class Github
    extend T::Sig

    sig { returns(String) }
    attr_reader :user_access_token

    sig { returns(String) }
    attr_reader :user_nickname

    sig { params(user_nickname: String, user_access_token: String).void }
    def initialize(user_nickname:, user_access_token:)
      @user_nickname = user_nickname
      @user_access_token = user_access_token
    end

    sig { returns(Octokit::Client) }
    def octokit_client
      client = Octokit::Client.new access_token: user_access_token
      client.auto_paginate = true
      client
    end

    # Will create a repository. Works for both an individual and an
    # organisation. Returns a repo
    sig { params(owner_nickname: String, name: String, description: T.nilable(String), private: T::Boolean).void }
    def create_repository(owner_nickname:, name:, description:, private:)
      options = { description: description, private: private, auto_init: true }
      options[:organization] = owner_nickname if user_nickname != owner_nickname
      octokit_client.create_repository(name, options)
    end

    # Returns a list of all public repos. Works for both an individual and
    # an organization. List is sorted by push date
    sig { params(owner_nickname: String).returns(T::Array[Repo]) }
    def public_repos(owner_nickname)
      repos = if user_nickname == owner_nickname
                octokit_client.repositories(owner_nickname,
                                            sort: :pushed, type: :public)
              else
                # This call doesn't seem to support sort by pushed.
                # So, doing it ourselves
                repos = octokit_client.organization_repositories(owner_nickname,
                                                                 type: :public)
                repos.sort { |a, b| b.pushed_at.to_i <=> a.pushed_at.to_i }
              end
      repos.map { |r| new_repo(r) }
    end

    # Needs user:email oauth scope for this to work
    # Will return nil if you don't have the right scope
    sig { returns(T.nilable(String)) }
    def primary_email
      # TODO: If email isn't verified probably should not send email to it
      octokit_client.emails(accept: "application/vnd.github.v3").find(&:primary)&.email
    rescue Octokit::NotFound, Octokit::Unauthorized
      nil
    end

    class Rel < T::Struct
      const :href, String
    end

    class OwnerRels < T::Struct
      const :avatar, Rel
    end

    class RepoRels < T::Struct
      const :html, Rel
      const :git, Rel
    end

    class Owner < T::Struct
      const :login, String
      const :name, T.nilable(String)
      const :blog, T.nilable(String)
      const :company, T.nilable(String)
      const :location, T.nilable(String)
      const :email, T.nilable(String)
      const :rels, OwnerRels
      const :id, Integer
    end

    class Repo < T::Struct
      const :owner, Owner
      const :name, String
      const :full_name, String
      const :description, T.nilable(String)
      const :id, Integer
      const :rels, RepoRels
    end

    sig { params(owner: T.untyped).returns(Owner) }
    def new_owner(owner)
      Owner.new(
        login: owner.login,
        name: owner.name,
        blog: owner.blog,
        company: owner.company,
        location: owner.location,
        email: owner.email,
        rels: new_owner_rels(owner.rels),
        id: owner.id
      )
    end

    sig { params(rel: T.untyped).returns(Rel) }
    def new_rel(rel)
      Rel.new(href: rel.href)
    end

    sig { params(rels: T.untyped).returns(OwnerRels) }
    def new_owner_rels(rels)
      OwnerRels.new(
        avatar: new_rel(rels[:avatar])
      )
    end

    sig { params(rels: T.untyped).returns(RepoRels) }
    def new_repo_rels(rels)
      RepoRels.new(
        html: new_rel(rels[:html]),
        git: new_rel(rels[:git])
      )
    end

    sig { params(repo: T.untyped).returns(Repo) }
    def new_repo(repo)
      Repo.new(
        owner: new_owner(repo.owner),
        name: repo.name,
        full_name: repo.full_name,
        description: repo.description,
        id: repo.id,
        rels: new_repo_rels(repo.rels)
      )
    end

    sig { params(full_name: String).returns(Repo) }
    def repository(full_name)
      new_repo(octokit_client.repository(full_name))
    end

    sig { params(repo_full_name: String, private: T::Boolean).void }
    def update_privacy(repo_full_name, private)
      if private
        octokit_client.set_private(repo_full_name)
      else
        octokit_client.set_public(repo_full_name)
      end
    end

    # Overwrites whatever there was before in that repo
    # Obviously use with great care
    sig { params(repo_full_name: String, files: T::Hash[String, String], message: String).void }
    def add_commit_to_root(repo_full_name, files, message)
      client = octokit_client
      blobs = files.map do |filename, content|
        {
          path: filename,
          mode: "100644",
          type: "blob",
          content: content
        }
      end
      tree = client.create_tree(repo_full_name, blobs)
      commit = client.create_commit(repo_full_name, message, tree.sha)
      client.update_ref(repo_full_name, "heads/main", commit.sha)
    end

    sig { params(repo_full_name: String, url: String).void }
    def update_repo_homepage(repo_full_name, url)
      octokit_client.edit_repository(repo_full_name, homepage: url)
    end

    sig { params(nickname: String).returns(Owner) }
    def organization(nickname)
      new_owner(octokit_client.organization(nickname))
    end

    sig { params(nickname: String).returns(T::Array[Owner]) }
    def organizations(nickname)
      octokit_client.organizations(nickname).map { |o| new_owner(o) }
    end

    # TODO: Figure out a better name for this method
    sig { params(nickname: String).returns(Owner) }
    def user_from_github(nickname)
      new_owner(octokit_client.user(nickname))
    end
  end
end
