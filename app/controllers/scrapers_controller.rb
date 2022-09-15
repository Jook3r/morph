# typed: strict
# frozen_string_literal: true

class ScrapersController < ApplicationController
  extend T::Sig

  before_action :authenticate_user!, except: %i[
    index show watchers history running
  ]
  before_action :load_resource, only: %i[
    settings show destroy update run stop clear watch
    watchers history
  ]

  # All methods
  # :settings, :index, :new, :create, :github, :github_form, :create_github,
  # :show, :destroy, :update, :run, :stop,
  # :clear, :watch, :watchers, :history, :running

  sig { void }
  def settings
    authorize! :settings, @scraper
  end

  sig { void }
  def index
    @scrapers = Scraper.accessible_by(current_ability).order(created_at: :desc)
                       .page(params[:page])
  end

  sig { void }
  def new
    @scraper = Scraper.new
    authorize! :new, @scraper
  end

  sig { void }
  def create
    params_scraper = T.cast(params[:scraper], ActionController::Parameters)
    authenticated_user = T.must(current_user)

    scraper = Scraper.new(
      original_language_key: params_scraper[:original_language_key],
      owner_id: params_scraper[:owner_id],
      name: params_scraper[:name],
      description: params_scraper[:description]
    )
    scraper.full_name = "#{scraper.owner.to_param}/#{scraper.name}"
    authorize! :create, scraper
    if scraper.valid?
      scraper.create_create_scraper_progress!(
        heading: "New scraper",
        message: "Queuing",
        progress: 5
      )
      scraper.save!
      CreateScraperWorker.perform_async(T.must(scraper.id), T.must(authenticated_user.id),
                                        scraper_url(scraper))
      redirect_to scraper
    else
      @scraper = scraper
      render :new
    end
  end

  sig { void }
  def github
    authorize! :github, Scraper
  end

  # For rendering ajax partial in github action
  sig { void }
  def github_form
    authorize! :github_form, Scraper
    @scraper = Scraper.new
    render partial: "github_form", locals: { scraper: @scraper, owner: Owner.find(params[:id]) }
  end

  sig { void }
  def create_github
    params_scraper = T.cast(params[:scraper], ActionController::Parameters)
    full_name = T.cast(params_scraper[:full_name], String)
    authenticated_user = T.must(current_user)

    scraper = Scraper.new_from_github(full_name, authenticated_user.octokit_client)
    authorize! :create_github, scraper
    if scraper.save
      scraper.create_create_scraper_progress!(
        heading: "Adding from GitHub",
        message: "Queuing",
        progress: 5
      )
      scraper.save!
      CreateFromGithubWorker.perform_async(T.must(scraper.id))
      redirect_to scraper
    else
      @scraper = scraper
      render :github
    end
  end

  sig { void }
  def show
    authorize! :show, @scraper
  end

  sig { void }
  def destroy
    scraper = T.must(@scraper)

    authorize! :destroy, scraper
    flash[:notice] = "Scraper #{scraper.name} deleted"
    scraper.destroy
    # TODO: Make this done by default after calling Scraper#destroy
    scraper.destroy_repo_and_data
    redirect_to scraper.owner
  end

  sig { void }
  def update
    scraper = T.must(@scraper)

    authorize! :update, scraper
    if scraper.update(scraper_params)
      sync_update scraper
      redirect_to scraper, notice: t(".success")
    else
      render :settings
    end
  end

  sig { void }
  def run
    scraper = T.must(@scraper)

    authorize! :run, scraper
    scraper.queue!
    scraper.reload
    sync_update scraper
    redirect_to scraper
  end

  sig { void }
  def stop
    scraper = T.must(@scraper)

    authorize! :stop, scraper
    scraper.stop!
    scraper.reload
    sync_update scraper
    redirect_to scraper
  end

  sig { void }
  def clear
    scraper = T.must(@scraper)

    authorize! :clear, scraper
    scraper.database.clear
    scraper.reindex
    redirect_to scraper
  end

  # Toggle whether we're watching this scraper
  sig { void }
  def watch
    scraper = T.must(@scraper)
    authenticated_user = T.must(current_user)

    authenticated_user.toggle_watch(scraper)
    redirect_back(fallback_location: root_path)
  end

  sig { void }
  def watchers
    authorize! :watchers, @scraper
  end

  sig { void }
  def history
    authorize! :history, @scraper
  end

  sig { void }
  def running
    authorize! :running, Scraper
    @scrapers = T.let(Scraper.running, T.nilable(T::Array[Scraper]))
  end

  private

  sig { void }
  def load_resource
    @scraper = T.let(Scraper.friendly.find(params[:id]), T.nilable(Scraper))
  end

  sig { returns(ActionController::Parameters) }
  def scraper_params
    s = T.cast(params.require(:scraper), ActionController::Parameters)
    if can? :memory_setting, @scraper
      s.permit(:auto_run, :memory_mb,
               variables_attributes: %i[
                 id name value _destroy
               ],
               webhooks_attributes: %i[
                 id url _destroy
               ])
    else
      s.permit(:auto_run,
               variables_attributes: %i[
                 id name value _destroy
               ],
               webhooks_attributes: %i[
                 id url _destroy
               ])
    end
  end
end
