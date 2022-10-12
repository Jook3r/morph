# typed: strict
# frozen_string_literal: true

module Morph
  # Service layer for talking to the Github API. Acts on behalf of a user
  class Github
    extend T::Sig

    sig { returns(User) }
    attr_reader :user

    sig { params(user: User).void }
    def initialize(user)
      @user = user
    end

    sig { returns(Octokit::Client) }
    def octokit_client
      client = Octokit::Client.new access_token: user.access_token
      client.auto_paginate = true
      client
    end

    # Will create a repository. Works for both an individual and an
    # organisation. Returns a repo
    sig { params(owner: Owner, name: String, description: T.nilable(String), private: T::Boolean).void }
    def create_repository(owner:, name:, description:, private:)
      options = { description: description, private: private, auto_init: true }
      options[:organization] = owner.nickname if user != owner
      octokit_client.create_repository(name, options)
    end

    # Returns a list of all public repos. Works for both an individual and
    # an organization. List is sorted by push date
    # TODO: Just pass in nickname of owner
    sig { params(owner: ::Owner).returns(T::Array[Repo]) }
    def public_repos(owner)
      if user == owner
        octokit_client.repositories(owner.nickname,
                                    sort: :pushed, type: :public)
      else
        # This call doesn't seem to support sort by pushed.
        # So, doing it ourselves
        repos = octokit_client.organization_repositories(owner.nickname,
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

    class Owner < T::Struct
      const :nickname, String
      const :login, String
      const :name, String
      const :blog, String
      const :company, String
      const :location, String
      const :email, String
      const :rels, Rels
      const :id, Integer
    end

    class Rel < T::Struct
      const :href, String
    end

    class Rels < T::Struct
      const :html, Rel
      const :git, Rel
      const :avatar, Rel
    end

    class Repo < T::Struct
      const :owner, Owner
      const :name, String
      const :full_name, String
      const :description, String
      const :id, Integer
      const :rels, Rels
    end

    sig { params(owner: T.untyped).returns(Owner) }
    def new_owner(owner)
      Owner.new(
        nickname: owner.nickname,
        login: owner.login,
        name: owner.name,
        blog: owner.blog,
        company: owner.company,
        location: owner.location,
        email: owner.email,
        rels: new_rels(owner.rels),
        id: owner.id
      )
    end

    sig { params(rel: T.untyped).returns(Rel) }
    def new_rel(rel)
      Rel.new(href: rel.href)
    end

    sig { params(rels: T.untyped).returns(Rels) }
    def new_rels(rels)
      Rels.new(
        html: new_rel(rels[:html]),
        git: new_rel(rels[:git]),
        avatar: new_rel(rels[:avatar])
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
        rels: new_rels(repo.rels)
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
    # TODO: Return properly typed object
    sig { params(nickname: String).returns(T.untyped) }
    def user_from_github(nickname)
      octokit_client.user(nickname)
    end
  end
end
