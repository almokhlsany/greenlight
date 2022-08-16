# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApiController
      skip_before_action :ensure_authenticated, only: %i[create]

      before_action only: %i[update purge_avatar] do
        ensure_authorized('ManageUsers', user_id: params[:id])
      end

      def show
        user = User.find(params[:id])

        render_data data: user, status: :ok
      end

      # POST /api/v1/users.json
      # Expects: { user: { :name, :email, :password, :password_confirmation } }
      # Returns: { data: Array[serializable objects] , errors: Array[String] }
      # Does: Creates and saves a new user record in the database with the provided parameters.

      def create
        # TODO: amir - ensure accessibility for unauthenticated requests only.
        params[:user][:language] = I18n.default_locale if params[:user][:language].blank?

        user = UserCreator.new(user_params:, provider: current_provider).call

        # TODO: Add proper error logging for non-verified token hcaptcha
        return render_error errors: user.errors.to_a if hcaptcha_enabled? && !verify_hcaptcha(response: params[:token])

        if user.save
          session[:user_id] ||= user.id
          token = user.generate_activation_token!
          render_data data: { token: }, status: :created # TODO: enable activation email sending.
        else
          # TODO: amir - Improve logging.
          render_error errors: user.errors.to_a
        end
      end

      # TODO: Add a before_action callback to update,destory and purge_avatar calling a find_user.
      def update
        user = User.find(params[:id])
        if user.update(user_params)
          render_data  status: :ok
        else
          render_error errors: user.errors.to_a
        end
      end

      def destroy
        user = User.find(params[:id])
        if user.destroy
          render_data  status: :ok
        else
          render_error errors: user.errors.to_a
        end
      end

      def purge_avatar
        user = User.find(params[:id])
        user.avatar.purge

        render_data status: :ok
      end

      # POST /api/v1/users/change_password.json
      # Expects: { user: { :old, :new } }
      # Returns: { data: Array[serializable objects] , errors: Array[String] }
      # Does: Validates and change the user password.

      def change_password
        return render_error status: :unauthorized unless current_user # TODO: generalise this.

        return render_error status: :forbidden if current_user.external_id?

        old_password = change_password_params[:old_password]
        new_password = change_password_params[:new_password]

        return render_error status: :bad_request if new_password.blank? || old_password.blank?

        return render_error status: :bad_request unless current_user.authenticate old_password

        current_user.update! password: new_password
        render_data status: :ok
      end

      private

      def user_params
        params.require(:user).permit(:name, :email, :password, :password_confirmation, :avatar, :language)
      end

      def change_password_params
        params.require(:user).permit(:old_password, :new_password)
      end
    end
  end
end
