# typed: false
# frozen_string_literal: true

module Morph
  class DockerMaintenance
    def self.delete_container(container)
      Rails.logger.info "Deleting container #{container.id}..."
      container.delete
    rescue StandardError => e
      Rails.logger.warn "Exception while removing container #{container.id}: #{e.inspect}"
    end

    def self.remove_image(image_id)
      Rails.logger.info "Removing image #{image_id}..."
      Docker::Image.get(image_id).remove
    rescue Docker::Error::ConflictError
      Rails.logger.warn "Conflict removing image, skipping..."
    rescue Docker::Error::NotFoundError
      Rails.logger.warn "Couldn't find container image, skipping..."
    end
  end
end
