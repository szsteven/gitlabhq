# frozen_string_literal: true

module API
  class GroupImport < Grape::API
    MAXIMUM_FILE_SIZE = 50.megabytes.freeze

    helpers do
      def parent_group
        find_group!(params[:parent_id]) if params[:parent_id].present?
      end

      def authorize_create_group!
        if parent_group
          authorize! :create_subgroup, parent_group
        else
          authorize! :create_group
        end
      end

      def closest_allowed_visibility_level
        if parent_group
          Gitlab::VisibilityLevel.closest_allowed_level(parent_group.visibility_level)
        else
          Gitlab::VisibilityLevel::PRIVATE
        end
      end
    end

    resource :groups, requirements: API::NAMESPACE_OR_PROJECT_REQUIREMENTS do
      desc 'Workhorse authorize the group import upload' do
        detail 'This feature was introduced in GitLab 12.8'
      end
      post 'import/authorize' do
        require_gitlab_workhorse!

        Gitlab::Workhorse.verify_api_request!(headers)

        status 200
        content_type Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE

        ImportExportUploader.workhorse_authorize(has_length: false, maximum_size: MAXIMUM_FILE_SIZE)
      end

      desc 'Create a new group import' do
        detail 'This feature was introduced in GitLab 12.8'
        success Entities::Group
      end
      params do
        requires :path, type: String, desc: 'Group path'
        requires :name, type: String, desc: 'Group name'
        optional :parent_id, type: Integer, desc: "The ID of the parent group that the group will be imported into. Defaults to the current user's namespace."
        optional 'file.path', type: String, desc: 'Path to locally stored body (generated by Workhorse)'
        optional 'file.name', type: String, desc: 'Real filename as send in Content-Disposition (generated by Workhorse)'
        optional 'file.type', type: String, desc: 'Real content type as send in Content-Type (generated by Workhorse)'
        optional 'file.size', type: Integer, desc: 'Real size of file (generated by Workhorse)'
        optional 'file.md5', type: String, desc: 'MD5 checksum of the file (generated by Workhorse)'
        optional 'file.sha1', type: String, desc: 'SHA1 checksum of the file (generated by Workhorse)'
        optional 'file.sha256', type: String, desc: 'SHA256 checksum of the file (generated by Workhorse)'
      end
      post 'import' do
        authorize_create_group!
        require_gitlab_workhorse!

        uploaded_file = UploadedFile.from_params(params, :file, ImportExportUploader.workhorse_local_upload_path)

        bad_request!('Unable to process group import file') unless uploaded_file

        group_params = {
          path: params[:path],
          name: params[:name],
          parent_id: params[:parent_id],
          visibility_level: closest_allowed_visibility_level,
          import_export_upload: ImportExportUpload.new(import_file: uploaded_file)
        }

        group = ::Groups::CreateService.new(current_user, group_params).execute

        if group.persisted?
          GroupImportWorker.perform_async(current_user.id, group.id) # rubocop:disable CodeReuse/Worker

          accepted!
        else
          render_api_error!("Failed to save group #{group.errors.messages}", 400)
        end
      end
    end
  end
end
