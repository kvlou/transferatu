require_relative 'helpers'

module Transferatu::Endpoints
  class Groups < Base
    include Serializer

    serialize_with Transferatu::Serializers::Group

    namespace "/groups" do
      before do
        content_type :json, charset: 'utf-8'
      end

      get do
        groups = current_user.groups_dataset.present.all
        respond serialize(groups)
      end

      post do
        begin
          group = Transferatu::Mediators::Groups::Creator.run(
                  user: current_user,
                  name: data["name"],
                  log_input_url: data["log_input_url"],
                  backup_limit: data["backup_limit"]
                )
          respond serialize(group), status: 201
        rescue Sequel::UniqueConstraintViolation
          raise Pliny::Errors::Conflict, "group #{data["name"]} already exists"
        end
      end

      get "/:name" do
        group = current_user.groups_dataset.present.where(name: params[:name]).first
        respond serialize(group)
      end

      delete "/:name" do
        group = current_user.groups_dataset.present.where(name: params[:name]).first
        if group.nil?
          raise Pliny::Errors::NotFound, "group #{params[:name]} not found"
        else
          group.destroy
          respond serialize(group)
        end
      end
    end
  end
end
