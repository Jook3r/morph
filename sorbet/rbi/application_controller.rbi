# typed: true

class ApplicationController
  sig { returns(T.nilable(User)) }
  def current_user; end

  def authenticate_user!; end

  def stored_location_for(resource); end

  def sync_update(model); end
end
